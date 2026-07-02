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


if __name__ == "__main__":
    unittest.main()
