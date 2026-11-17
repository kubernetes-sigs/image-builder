#!/usr/bin/env python3

# Copyright 2026 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Exercise Photon's package transactions with real tdnf and fixture RPMs."""

import json
import pathlib
import shlex
import shutil
import subprocess
import tempfile
import unittest

import jinja2
import yaml


ROOT = pathlib.Path(__file__).resolve().parents[1]
BOOTSTRAP = {"cloud-init", "open-vm-tools", "openssh-server", "python3", "sudo"}


class PhotonPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for command in ("tdnf", "rpm", "rpmbuild", "createrepo_c"):
            if not shutil.which(command):
                raise RuntimeError(
                    f"{command} is required; run these tests in a Photon container "
                    "as documented in docs/book/src/capi/providers/vsphere.md"
                )
        cls.scratch = tempfile.TemporaryDirectory(prefix="image-builder-photon-")
        cls.addClassCleanup(cls.scratch.cleanup)
        cls.root = pathlib.Path(cls.scratch.name)
        cls.defaults = yaml.safe_load(
            (ROOT / "ansible/roles/node/defaults/main.yml").read_text()
        )
        cls.goss = yaml.safe_load((ROOT / "packer/goss/goss-vars.yaml").read_text())
        cls.tasks = yaml.safe_load(
            (ROOT / "ansible/roles/setup/tasks/photon.yml").read_text()
        )
        cls.kickstarts = {
            version: json.loads(
                (ROOT / f"packer/ova/linux/photon/http/{version}/ks.json.tmpl").read_text()
            )["packages"]
            for version in ("4", "5")
        }
        names = BOOTSTRAP | {"alternatives", "photon-repos", "toybox"}
        for version in ("4", "5"):
            names.update(cls.kickstarts[version])
            names.update(cls.defaults[f"photon_{version}_rpms"])
        names.update(cls.defaults["common_photon_rpms"])
        names.update(cls.defaults["common_virt_photon_rpms"])
        cls.legacy = cls.build_repo("legacy", names - {"hostname"}, False)
        cls.current = cls.build_repo("current", names, True)

    @classmethod
    def build_repo(cls, name, names, current):
        build = cls.root / name
        build.mkdir()
        spec = [
            "Name: image-builder-photon-fixture",
            "Version: 1",
            "Release: 1",
            "Summary: Photon package transition fixtures",
            "License: Apache-2.0",
            "BuildArch: noarch",
            "%description",
            "Empty packages with the GA and updated network-tool dependencies.",
        ]
        for package in sorted(names):
            updated = current and package in {
                "cloud-init", "open-vm-tools", "hostname", "toybox", "net-tools"
            }
            spec.extend([
                f"%package -n {package}",
                f"Summary: {package} fixture",
                f"Version: {2 if updated else 1}",
            ])
            if package in {"cloud-init", "open-vm-tools"}:
                spec.append(f"Requires: {'hostname' if current else 'net-tools'}")
            if package == "cloud-init":
                spec.append("Requires: python3")
            if updated and package in {"hostname", "toybox"}:
                spec.append("Conflicts: net-tools")
            if updated and package == "net-tools":
                spec.append("Conflicts: hostname")
            spec.extend([f"%description -n {package}", f"{package} fixture."])
        spec.append("%files")
        spec.extend(f"%files -n {package}" for package in sorted(names))
        spec_path = build / "fixtures.spec"
        spec_path.write_text("\n".join(spec) + "\n")
        subprocess.run(
            ["rpmbuild", "-bb", "--define", f"_topdir {build}", str(spec_path)],
            check=True, stdout=subprocess.DEVNULL,
        )
        repo = build / "RPMS/noarch"
        subprocess.run(
            ["createrepo_c", str(repo)], check=True, stdout=subprocess.DEVNULL,
        )
        return repo

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.work.cleanup)
        self.installroot = pathlib.Path(self.work.name) / "system"
        self.installroot.mkdir()
        self.repos = pathlib.Path(self.work.name) / "repos"
        self.repos.mkdir()
        self.use_repo(self.legacy)

    def use_repo(self, path):
        (self.repos / "photon.repo").write_text(
            f"[photon]\nname=Photon fixture\nbaseurl={path.as_uri()}\n"
            "enabled=1\ngpgcheck=0\n"
        )

    def tdnf(self, *args, check=True):
        result = subprocess.run(
            [
                "tdnf", "--installroot", str(self.installroot), "--releasever=5.0",
                f"--setopt=reposdir={self.repos}", *args,
            ],
            capture_output=True, text=True,
        )
        if check:
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result

    def installed(self):
        return set(subprocess.check_output(
            ["rpm", "--root", str(self.installroot), "-qa", "--qf", "%{NAME}\n"],
            text=True,
        ).splitlines())

    def bootstrap(self, version):
        self.tdnf("install", "-y", *self.kickstarts[version], "toybox")
        self.assertLessEqual(BOOTSTRAP, self.installed())

    def run_setup_packages(self, version):
        environment = jinja2.Environment(undefined=jinja2.StrictUndefined)
        environment.filters["bool"] = bool
        variables = {
            **self.defaults,
            "ansible_facts": {"distribution_major_version": version},
            "disable_public_repos": False,
            "extra_rpms": "",
            "rpms": (
                self.defaults["common_photon_rpms"]
                + self.defaults[f"photon_{version}_rpms"]
                + self.defaults["common_virt_photon_rpms"]
            ),
        }
        for task in self.tasks:
            condition = task.get("when")
            if condition and not environment.compile_expression(condition)(**variables):
                continue
            for key, value in task.get("ansible.builtin.set_fact", {}).items():
                variables[key] = environment.from_string(value).render(**variables)
            command = task.get("ansible.builtin.command")
            if command:
                self.tdnf(*shlex.split(
                    environment.from_string(command).render(**variables)
                )[1:])
                self.assertLessEqual(
                    BOOTSTRAP, self.installed(),
                    f"Bootstrap packages were removed by {task['name']}",
                )
        expected = (
            self.goss["common_photon_rpms"].keys()
            | self.goss[f"photon_{version}_rpms"].keys()
        )
        self.assertLessEqual(expected, self.installed())

    def test_ga_photon_5_migrates_without_removing_bootstrap_packages(self):
        self.bootstrap("5")
        self.assertIn("net-tools", self.installed())
        self.use_repo(self.current)
        self.run_setup_packages("5")
        self.assertNotIn("net-tools", self.installed())
        self.run_setup_packages("5")

    def test_current_photon_5_kickstart_and_setup_are_compatible(self):
        self.use_repo(self.current)
        self.bootstrap("5")
        self.run_setup_packages("5")
        self.assertNotIn("net-tools", self.installed())

    def test_photon_4_keeps_net_tools_and_needs_no_hostname_package(self):
        self.bootstrap("4")
        self.run_setup_packages("4")
        self.assertIn("net-tools", self.installed())
        self.assertNotIn("hostname", self.installed())

    def test_old_and_new_network_packages_cannot_be_requested_together(self):
        self.bootstrap("5")
        self.use_repo(self.current)
        result = self.tdnf(
            "install", "-y", "--refresh", "net-tools", "hostname", "toybox",
            "cloud-init", "open-vm-tools", check=False,
        )
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertLessEqual(BOOTSTRAP, self.installed())


if __name__ == "__main__":
    unittest.main()
