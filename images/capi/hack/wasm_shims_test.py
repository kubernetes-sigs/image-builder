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

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest

import yaml
from ansible.parsing.dataloader import DataLoader
from ansible.parsing.splitter import parse_kv
from ansible.playbook.conditional import Conditional
from ansible.template import Templar


ROOT = Path(__file__).resolve().parents[1]
RUNTIMES = "containerd_wasm_shims_runtimes"
SHIMS = ("lunatic", "slight", "spin", "wws")
ROLE = ROOT / "ansible/roles/containerd"


def read_json(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


class WasmShimsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        local_packer = ROOT / ".local/bin/packer"
        cls.packer = os.environ.get("PACKER_BIN") or (
            str(local_packer) if local_packer.is_file() else shutil.which("packer")
        )
        if not cls.packer:
            raise RuntimeError("Packer is required; run make deps-common first")

    def console(self, expression, flags=(), template=None):
        result = subprocess.run(
            [self.packer, "console", *flags, *([str(template)] if template else [])],
            input=expression + "\n",
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result.stdout.strip()

    def build_commands(self, *targets, packer_flags="", var_files=""):
        result = subprocess.run(
            [
                "make", "--no-print-directory", "-n",
                "PACKER=packer", "FLATCAR_VERSION=3815.2.0",
                f"PACKER_FLAGS={packer_flags}", f"PACKER_VAR_FILES={var_files}",
                *targets,
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=True,
        )
        commands = []
        for line in result.stdout.splitlines():
            if "packer build " not in line:
                continue
            args = shlex.split(line)
            for index in range(len(args) - 1):
                if args[index:index + 2] == ["packer", "build"]:
                    commands.append(args[index + 2:])
        self.assertTrue(commands, result.stdout)
        return commands

    def build_console(self, command, expression):
        flags = []
        args = iter(command[:-1])
        for arg in args:
            if arg in ("-var", "--var", "-var-file", "--var-file"):
                flags.extend([arg, next(args)])
            elif arg.startswith(("-var=", "--var=", "-var-file=", "--var-file=")):
                flags.append(arg)
        return self.console(expression, flags, command[-1])

    def selection(self, command):
        selection = self.build_console(command, "{{user `" + RUNTIMES + "`}}")
        template = read_json(command[-1])
        for provisioner in template["provisioners"]:
            if provisioner["type"] == "goss" and RUNTIMES in provisioner["vars_inline"]:
                self.assertEqual(
                    selection,
                    self.build_console(command, provisioner["vars_inline"][RUNTIMES]),
                )
        return selection

    def test_default_builds_do_not_enable_shims(self):
        commands = self.build_commands(
            "build-azure-sigs",
            "build-ami-ubuntu-2404", "build-gce-ubuntu-2404",
            "build-do-ubuntu-2404", "build-oxide-ubuntu-2404",
            "build-huaweicloud-ubuntu-2204", "build-openstack-ubuntu-2404",
            "build-osc-ubuntu-2404", "build-oci-ubuntu-2204",
            "build-powervs-centos-9", "build-hcloud-ubuntu-2404",
            "build-hcloud-flatcar", "build-vultr-ubuntu-2404",
            "build-scaleway-ubuntu-2404",
        )
        for command in commands:
            if command[-1].endswith("packer-windows.json"):
                continue
            with self.subTest(command=command):
                self.assertEqual("", self.selection(command))

    def test_azure_presubmit_defaults_do_not_enable_shims(self):
        script = (ROOT / "scripts/ci-azure-e2e.sh").read_text(encoding="utf-8")
        var_files = re.search(r'^export PACKER_VAR_FILES="([^"]+)"$', script, re.MULTILINE)
        self.assertIsNotNone(var_files)
        commands = [
            command
            for command in self.build_commands("build-azure-sigs", var_files=var_files.group(1))
            if command[-1].endswith("packer/azure/packer.json")
        ]
        self.assertTrue(commands)
        for command in commands:
            with self.subTest(command=command):
                self.assertEqual("", self.selection(command))

    def test_explicit_opt_in_with_var_file_and_cli(self):
        targets = (
            "build-azure-sig-azurelinux-3", "build-azure-sig-azurelinux-3-gen2",
            "build-azure-sig-flatcar", "build-hcloud-flatcar", "build-ami-ubuntu-2404",
        )
        with tempfile.TemporaryDirectory() as tmp:
            var_file = Path(tmp) / "wasm.json"
            var_file.write_text(json.dumps({RUNTIMES: "spin"}), encoding="utf-8")
            for overrides in (
                {"var_files": str(var_file)},
                {"packer_flags": f"--var {RUNTIMES}=spin"},
            ):
                for command in self.build_commands(*targets, **overrides):
                    with self.subTest(overrides=overrides, command=command):
                        self.assertEqual("spin", self.selection(command))

    def test_nutanix_standalone_default_and_opt_in(self):
        for selection in ("", "spin"):
            flags = [f"-var={RUNTIMES}={selection}"] if selection else []
            with self.subTest(selection=selection):
                self.assertEqual(
                    selection,
                    self.console(f"var.{RUNTIMES}", flags, "packer/nutanix"),
                )
                self.assertIn(
                    f'{RUNTIMES}="{selection}"',
                    self.console("local.ansible_common_vars", flags, "packer/nutanix"),
                )

    def test_ansible_installation_and_registration_follow_selection(self):
        tasks = yaml.safe_load((ROLE / "tasks/main.yml").read_text(encoding="utf-8"))
        shim_tasks = [task for task in tasks if "containerd-wasm-shims" in task["name"]]
        self.assertEqual(4, len(shim_tasks))
        template = (ROLE / "templates/etc/containerd/config.toml").read_text(encoding="utf-8")
        command = self.build_commands("build-azure-sig-azurelinux-3")[0]
        defaults = {
            **parse_kv(self.build_console(command, "{{user `ansible_common_vars`}}")),
            "packer_builder_type": "azure-arm",
        }
        defaults["runtime_versions"] = json.loads(
            defaults["containerd_wasm_shims_runtime_versions"]
        )
        loader = DataLoader()
        for selection in ("", "spin", ",".join(SHIMS)):
            for family in ("Debian", "Microsoft Azure Linux", "Flatcar"):
                variables = {
                    **defaults,
                    RUNTIMES: selection,
                    "ansible_facts": {"os_family": family},
                }
                templar = Templar(loader=loader, variables=variables)
                with self.subTest(selection=selection, family=family):
                    for task in shim_tasks:
                        condition = Conditional(loader=loader)
                        condition.when = (
                            [task["when"]] if isinstance(task["when"], str) else task["when"]
                        )
                        expected = bool(selection)
                        if task["name"].startswith("Unpack"):
                            expected &= ("Flatcar" in task["name"]) == (family == "Flatcar")
                        self.assertEqual(
                            expected,
                            condition.evaluate_conditional(templar, variables),
                            task["name"],
                        )
                        if expected:
                            self.assertEqual(
                                selection.split(","), templar.template(task["loop"])
                            )
                    config = templar.template(template)
                    self.assertIn("containerd.runtimes.runc]", config)
                    for shim in SHIMS:
                        self.assertEqual(
                            shim in selection.split(","),
                            f"containerd.runtimes.{shim}]" in config,
                            shim,
                        )


if __name__ == "__main__":
    unittest.main()
