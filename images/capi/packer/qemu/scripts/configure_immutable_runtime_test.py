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
            env={**os.environ, "IMMUTABLE_SYSTEMD_MOUNT_ORDERING_SERVICES": "", **env},
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
                    "IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS": "defaults,noatime,x-systemd.device-timeout=30s",
                    "IMMUTABLE_READ_ONLY_ROOT": "true",
                }
            )

            rendered = fstab.read_text(encoding="utf-8")
            self.assertIn(
                f"LABEL=CAPI-DATA {data_mount} ext4 defaults,noatime,x-systemd.device-timeout=30s 0 2",
                rendered,
            )
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
                "IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS": "defaults,x-systemd.device-timeout=30s",
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
                    "IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS": "defaults,x-systemd.device-timeout=30s",
                    "IMMUTABLE_PERSISTENT_PATHS": str(persistent_path),
                }
            )

            rendered = fstab.read_text(encoding="utf-8")
            persistent_source = data_mount / "persistent" / str(persistent_path).lstrip("/")
            self.assertIn(
                f"{persistent_source} {persistent_path} none bind,x-systemd.requires-mounts-for={data_mount} 0 0",
                rendered,
            )
            self.assertEqual("node config\n", (persistent_source / "kubelet.conf").read_text(encoding="utf-8"))

    def test_persistent_bind_mount_source_preserves_directory_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            workdir = pathlib.Path(tmp)
            fstab = workdir / "fstab"
            data_mount = workdir / "cluster-api-data"
            persistent_path = workdir / "root"
            fstab.write_text("/dev/sda1 / ext4 defaults 0 1\n", encoding="utf-8")
            persistent_path.mkdir(parents=True)
            persistent_path.chmod(0o700)

            self.run_script(
                {
                    "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                    "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                    "IMMUTABLE_RUNTIME_SUDO": "",
                    "IMMUTABLE_DATA_PARTITION": "true",
                    "IMMUTABLE_DATA_PARTITION_LABEL": "CAPI-DATA",
                    "IMMUTABLE_DATA_PARTITION_MOUNT": str(data_mount),
                    "IMMUTABLE_DATA_PARTITION_FSTYPE": "ext4",
                    "IMMUTABLE_PERSISTENT_PATHS": str(persistent_path),
                }
            )

            persistent_source = data_mount / "persistent" / str(persistent_path).lstrip("/")
            self.assertEqual(0o700, persistent_source.stat().st_mode & 0o777)

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
                    "IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS": "defaults,x-systemd.device-timeout=30s",
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
                f"{persistent_source} {persistent_path} none bind,x-systemd.requires-mounts-for={data_mount} 0 0",
                persistent_fstab,
            )
            self.assertIn(f"tmpfs {tmpfs_path} tmpfs mode=1777,nosuid,nodev 0 0", persistent_fstab)
            self.assertIn("/dev/sda1 / ext4 ro,relatime 0 1", persistent_fstab)

    def test_systemd_mount_ordering_dropins_are_synced_into_persistent_etc(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / "root"
            fstab = root / "etc" / "fstab"
            data_mount = root / "cluster-api-data"
            persistent_path = root / "etc"
            systemd_dir = root / "etc" / "systemd" / "system"
            fstab.parent.mkdir(parents=True)
            fstab.write_text("/dev/sda1 / ext4 defaults 0 1\n", encoding="utf-8")

            self.run_script(
                {
                    "IMMUTABLE_RUNTIME_FSTAB_PATH": str(fstab),
                    "IMMUTABLE_RUNTIME_SKIP_MOUNT": "true",
                    "IMMUTABLE_RUNTIME_SUDO": "",
                    "IMMUTABLE_RUNTIME_SYSTEMD_DIR": str(systemd_dir),
                    "IMMUTABLE_DATA_PARTITION": "true",
                    "IMMUTABLE_DATA_PARTITION_LABEL": "CAPI-DATA",
                    "IMMUTABLE_DATA_PARTITION_MOUNT": str(data_mount),
                    "IMMUTABLE_DATA_PARTITION_FSTYPE": "ext4",
                    "IMMUTABLE_PERSISTENT_PATHS": str(persistent_path),
                    "IMMUTABLE_TMPFS_PATHS": str(root / "tmp"),
                    "IMMUTABLE_SYSTEMD_MOUNT_ORDERING_SERVICES": "cloud-init-local.service,containerd.service,kubelet.service",
                }
            )

            persistent_source = data_mount / "persistent" / str(persistent_path).lstrip("/")
            for service in ("cloud-init-local.service", "containerd.service", "kubelet.service"):
                dropin = systemd_dir / f"{service}.d" / "10-immutable-runtime-mounts.conf"
                persistent_dropin = (
                    persistent_source / "systemd" / "system" / f"{service}.d" / "10-immutable-runtime-mounts.conf"
                )
                self.assertTrue(dropin.is_file())
                self.assertEqual(dropin.read_text(encoding="utf-8"), persistent_dropin.read_text(encoding="utf-8"))
                self.assertIn(f"RequiresMountsFor={data_mount} {persistent_path}", dropin.read_text(encoding="utf-8"))

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
            "/opt",
            "/srv",
            "/usr/local",
            "/var/backups",
            "/var/cache",
            "/var/crash",
            "/var/lib",
            "/var/local",
            "/var/log",
            "/var/mail",
            "/var/opt",
            "/var/spool",
        }

        self.assertEqual("true", values["immutable_data_partition"])
        self.assertEqual("/.capi-data", values["immutable_data_partition_mount"])
        self.assertNotIn("nofail", values["immutable_data_partition_mount_options"].split(","))
        self.assertEqual("true", values["immutable_read_only_root"])
        self.assertTrue(expected_paths.issubset(persistent_paths))
        self.assertFalse(any(path.startswith("/etc/") for path in persistent_paths))
        self.assertFalse(any(path.startswith("/var/lib/") for path in persistent_paths))


if __name__ == "__main__":
    unittest.main()
