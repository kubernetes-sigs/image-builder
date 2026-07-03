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
import pathlib
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("configure_immutable_runtime.sh")


class ConfigureImmutableRuntimeTests(unittest.TestCase):
    def run_script(self, env):
        subprocess.run(
            ["bash", str(SCRIPT)],
            check=True,
            env={**os.environ, **env},
            text=True,
            capture_output=True,
        )

    def test_configures_data_partition_and_read_only_root_in_fstab(self):
        with tempfile.TemporaryDirectory() as tmp:
            workdir = pathlib.Path(tmp)
            fstab = workdir / "fstab"
            data_mount = workdir / "cluster-api-data"
            fstab.write_text("/dev/sda1 / ext4 rw,relatime 0 1\n", encoding="utf-8")

            self.run_script(
                {
                    "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                    "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                    "IMMUTABLE_RUNTIME_SUDO": "",
                    "IMMUTABLE_DATA_PARTITION": "true",
                    "IMMUTABLE_DATA_PARTITION_LABEL": "CAPI-DATA",
                    "IMMUTABLE_DATA_PARTITION_MOUNT": str(data_mount),
                    "IMMUTABLE_DATA_PARTITION_FSTYPE": "ext4",
                    "IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS": "defaults,nofail,noatime",
                    "IMMUTABLE_READ_ONLY_ROOT": "true",
                }
            )

            rendered = fstab.read_text(encoding="utf-8")
            self.assertIn(f"LABEL=CAPI-DATA {data_mount} ext4 defaults,nofail,noatime 0 2", rendered)
            self.assertIn("/dev/sda1 / ext4 ro,relatime 0 1", rendered)
            self.assertTrue(data_mount.is_dir())

    def test_fstab_entries_are_replaced_instead_of_duplicated(self):
        with tempfile.TemporaryDirectory() as tmp:
            workdir = pathlib.Path(tmp)
            fstab = workdir / "fstab"
            data_mount = workdir / "data"
            fstab.write_text(
                "\n".join(
                    [
                        "/dev/sda1 / ext4 defaults 0 1",
                        f"LABEL=CAPI-DATA {data_mount} ext4 defaults 0 2",
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            env = {
                "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                "IMMUTABLE_RUNTIME_SUDO": "",
                "IMMUTABLE_DATA_PARTITION": "true",
                "IMMUTABLE_DATA_PARTITION_LABEL": "CAPI-DATA",
                "IMMUTABLE_DATA_PARTITION_MOUNT": str(data_mount),
                "IMMUTABLE_DATA_PARTITION_FSTYPE": "ext4",
                "IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS": "defaults,nofail",
                "IMMUTABLE_READ_ONLY_ROOT": "true",
            }
            self.run_script(env)
            self.run_script(env)

            lines = [line for line in fstab.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual(2, len(lines))
            self.assertEqual(1, sum(1 for line in lines if f" {data_mount} " in line))
            self.assertEqual(1, sum(1 for line in lines if " / " in line))

    def test_leaves_fstab_unchanged_when_disabled(self):
        with tempfile.TemporaryDirectory() as tmp:
            fstab = pathlib.Path(tmp) / "fstab"
            original = "/dev/sda1 / ext4 defaults 0 1\n"
            fstab.write_text(original, encoding="utf-8")

            self.run_script(
                {
                    "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                    "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                    "IMMUTABLE_RUNTIME_SUDO": "",
                    "IMMUTABLE_DATA_PARTITION": "false",
                    "IMMUTABLE_READ_ONLY_ROOT": "false",
                }
            )

            self.assertEqual(original, fstab.read_text(encoding="utf-8"))

    def test_configures_persistent_bind_mounts_and_copies_existing_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            workdir = pathlib.Path(tmp)
            fstab = workdir / "fstab"
            data_mount = workdir / "cluster-api-data"
            persistent_path = workdir / "etc" / "kubernetes"
            persisted_file = persistent_path / "kubelet.conf"
            fstab.write_text("/dev/sda1 / ext4 defaults 0 1\n", encoding="utf-8")
            persistent_path.mkdir(parents=True)
            persisted_file.write_text("node config\n", encoding="utf-8")

            self.run_script(
                {
                    "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                    "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                    "IMMUTABLE_RUNTIME_SUDO": "",
                    "IMMUTABLE_DATA_PARTITION": "true",
                    "IMMUTABLE_DATA_PARTITION_LABEL": "CAPI-DATA",
                    "IMMUTABLE_DATA_PARTITION_MOUNT": str(data_mount),
                    "IMMUTABLE_DATA_PARTITION_FSTYPE": "ext4",
                    "IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS": "defaults,nofail",
                    "IMMUTABLE_PERSISTENT_PATHS": str(persistent_path),
                }
            )

            rendered = fstab.read_text(encoding="utf-8")
            persistent_source = data_mount / "persistent" / str(persistent_path).lstrip("/")
            self.assertIn(
                f"{persistent_source} {persistent_path} none bind,nofail,x-systemd.requires-mounts-for={data_mount} 0 0",
                rendered,
            )
            self.assertEqual("node config\n", (persistent_source / "kubelet.conf").read_text(encoding="utf-8"))

    def test_persistent_etc_gets_final_fstab_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / "root"
            fstab = root / "etc" / "fstab"
            data_mount = root / "cluster-api-data"
            persistent_path = root / "etc"
            tmpfs_path = root / "tmp"
            fstab.parent.mkdir(parents=True)
            tmpfs_path.mkdir(parents=True)
            fstab.write_text("/dev/sda1 / ext4 rw,relatime 0 1\n", encoding="utf-8")

            self.run_script(
                {
                    "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                    "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                    "IMMUTABLE_RUNTIME_SUDO": "",
                    "IMMUTABLE_DATA_PARTITION": "true",
                    "IMMUTABLE_DATA_PARTITION_LABEL": "CAPI-DATA",
                    "IMMUTABLE_DATA_PARTITION_MOUNT": str(data_mount),
                    "IMMUTABLE_DATA_PARTITION_FSTYPE": "ext4",
                    "IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS": "defaults,nofail",
                    "IMMUTABLE_PERSISTENT_PATHS": str(persistent_path),
                    "IMMUTABLE_TMPFS_PATHS": str(tmpfs_path),
                    "IMMUTABLE_READ_ONLY_ROOT": "true",
                }
            )

            persistent_source = data_mount / "persistent" / str(persistent_path).lstrip("/")
            root_fstab = fstab.read_text(encoding="utf-8")
            persistent_fstab = (persistent_source / "fstab").read_text(encoding="utf-8")
            self.assertEqual(root_fstab, persistent_fstab)
            self.assertIn(
                f"{persistent_source} {persistent_path} none bind,nofail,x-systemd.requires-mounts-for={data_mount} 0 0",
                persistent_fstab,
            )
            self.assertIn(f"tmpfs {tmpfs_path} tmpfs mode=1777,nosuid,nodev 0 0", persistent_fstab)
            self.assertIn("/dev/sda1 / ext4 ro,relatime 0 1", persistent_fstab)

    def test_configures_multiple_tmpfs_paths_without_dropping_entries(self):
        with tempfile.TemporaryDirectory() as tmp:
            workdir = pathlib.Path(tmp)
            fstab = workdir / "fstab"
            first_tmpfs_path = workdir / "tmp"
            second_tmpfs_path = workdir / "var" / "tmp"
            fstab.write_text("/dev/sda1 / ext4 defaults 0 1\n", encoding="utf-8")

            self.run_script(
                {
                    "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                    "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                    "IMMUTABLE_RUNTIME_SUDO": "",
                    "IMMUTABLE_DATA_PARTITION": "false",
                    "IMMUTABLE_READ_ONLY_ROOT": "false",
                    "IMMUTABLE_TMPFS_PATHS": f"{first_tmpfs_path},{second_tmpfs_path}",
                }
            )

            lines = fstab.read_text(encoding="utf-8").splitlines()
            self.assertIn(f"tmpfs {first_tmpfs_path} tmpfs mode=1777,nosuid,nodev 0 0", lines)
            self.assertIn(f"tmpfs {second_tmpfs_path} tmpfs mode=1777,nosuid,nodev 0 0", lines)

    def test_persistent_paths_require_data_partition(self):
        with tempfile.TemporaryDirectory() as tmp:
            workdir = pathlib.Path(tmp)
            fstab = workdir / "fstab"
            fstab.write_text("/dev/sda1 / ext4 defaults 0 1\n", encoding="utf-8")

            result = subprocess.run(
                ["bash", str(SCRIPT)],
                check=False,
                env={
                    **os.environ,
                    "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                    "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                    "IMMUTABLE_RUNTIME_SUDO": "",
                    "IMMUTABLE_DATA_PARTITION": "false",
                    "IMMUTABLE_PERSISTENT_PATHS": str(workdir / "var" / "lib" / "kubelet"),
                },
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(0, result.returncode)
            self.assertIn("IMMUTABLE_PERSISTENT_PATHS requires IMMUTABLE_DATA_PARTITION=true", result.stderr)

    def test_ubuntu_immutable_target_defaults_cover_node_runtime_writes(self):
        target = SCRIPT.parent.parent / "qemu-ubuntu-2404-immutable.json"
        values = json.loads(target.read_text(encoding="utf-8"))

        persistent_paths = set(values["immutable_persistent_paths"].split(","))
        expected_paths = {
            "/etc",
            "/home",
            "/root",
            "/opt/cni/bin",
            "/var/cache",
            "/var/lib/NetworkManager",
            "/var/lib/calico",
            "/var/lib/chrony",
            "/var/lib/cilium",
            "/var/lib/cloud",
            "/var/lib/cni",
            "/var/lib/containerd",
            "/var/lib/dbus",
            "/var/lib/etcd",
            "/var/lib/kubelet",
            "/var/lib/private",
            "/var/lib/systemd",
            "/var/log",
            "/var/spool",
        }

        self.assertEqual("true", values["immutable_data_partition"])
        self.assertEqual("true", values["immutable_read_only_root"])
        self.assertTrue(expected_paths.issubset(persistent_paths))
        self.assertFalse(any(path.startswith("/etc/") for path in persistent_paths))


if __name__ == "__main__":
    unittest.main()
