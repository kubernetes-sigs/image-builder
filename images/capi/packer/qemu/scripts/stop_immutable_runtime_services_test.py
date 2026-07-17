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


SCRIPT = pathlib.Path(__file__).with_name("stop_immutable_runtime_services.sh")

FAKE_SYSTEMCTL_ALL_PRESENT = """#!/usr/bin/env bash
case "$1" in
  list-unit-files)
    echo "$2 enabled"
    ;;
  stop)
    echo "$2" >> "$STOP_LOG"
    ;;
esac
"""

FAKE_SYSTEMCTL_CONTAINERD_MISSING = """#!/usr/bin/env bash
case "$1" in
  list-unit-files)
    if [ "$2" = "containerd.service" ]; then
      exit 0
    fi
    echo "$2 enabled"
    ;;
  stop)
    echo "$2" >> "$STOP_LOG"
    ;;
esac
"""

FAKE_SYSTEMCTL_STOP_FAILS = """#!/usr/bin/env bash
case "$1" in
  list-unit-files)
    echo "$2 enabled"
    ;;
  stop)
    echo "failed to stop $2" >&2
    exit 1
    ;;
esac
"""


class StopImmutableRuntimeServicesTests(unittest.TestCase):
    def run_script(self, fake_systemctl, env):
        with tempfile.TemporaryDirectory() as tmp:
            workdir = pathlib.Path(tmp)
            fake_bin = workdir / "bin"
            fake_bin.mkdir()
            systemctl = fake_bin / "systemctl"
            systemctl.write_text(fake_systemctl, encoding="utf-8")
            systemctl.chmod(0o755)
            stop_log = workdir / "stop.log"

            result = subprocess.run(
                ["bash", str(SCRIPT)],
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "STOP_LOG": str(stop_log),
                    **env,
                },
                text=True,
                capture_output=True,
            )
            stopped = stop_log.read_text(encoding="utf-8").splitlines() if stop_log.exists() else []
            return result, stopped

    def test_stops_both_services_when_data_partition_enabled(self):
        result, stopped = self.run_script(
            FAKE_SYSTEMCTL_ALL_PRESENT, {"IMMUTABLE_DATA_PARTITION": "true"}
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual({"kubelet.service", "containerd.service"}, set(stopped))

    def test_skips_stop_when_immutable_target_disabled(self):
        result, stopped = self.run_script(
            FAKE_SYSTEMCTL_ALL_PRESENT,
            {
                "IMMUTABLE_DATA_PARTITION": "false",
                "IMMUTABLE_READ_ONLY_ROOT": "false",
                "IMMUTABLE_PERSISTENT_PATHS": "",
            },
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual([], stopped)

    def test_tolerates_absent_unit_without_failing(self):
        result, stopped = self.run_script(
            FAKE_SYSTEMCTL_CONTAINERD_MISSING, {"IMMUTABLE_READ_ONLY_ROOT": "true"}
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(["kubelet.service"], stopped)
        self.assertIn("containerd.service", result.stderr)
        self.assertIn("unit not found", result.stderr)

    def test_real_stop_failure_fails_the_build(self):
        result, stopped = self.run_script(
            FAKE_SYSTEMCTL_STOP_FAILS, {"IMMUTABLE_PERSISTENT_PATHS": "/etc"}
        )

        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], stopped)
        self.assertIn("failed to stop kubelet.service", result.stderr)


if __name__ == "__main__":
    unittest.main()
