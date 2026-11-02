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
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "ansible/roles/sysprep/files/azurelinux-core-diagnostics.sh"
TEMPLATE = ROOT / "packer/azure/packer.json"
PACKER = os.environ.get("PACKER_BIN") or shutil.which("packer") or str(
    ROOT / ".local/bin/packer"
)
JOURNAL_FIELDS = {
    "COREDUMP_COMM",
    "COREDUMP_EXE",
    "COREDUMP_FILENAME",
    "COREDUMP_SIGNAL",
    "COREDUMP_TIMESTAMP",
}
CORE_CONTENT = b"\x7fELFPRIVATE_CORE_MEMORY_MUST_NOT_BE_LOGGED"
FAKE_JOURNALCTL = """#!/usr/bin/env bash
printf '%s\\n' "$@" > "$JOURNAL_ARGS"
if [[ "${JOURNAL_RC:-0}" != "0" ]]; then
  echo "fixture journal query failed" >&2
  exit "$JOURNAL_RC"
fi
echo '{"COREDUMP_COMM":"fixture-process","COREDUMP_SIGNAL":"11"}'
"""


class AzureLinuxCoreDiagnosticsTests(unittest.TestCase):
    def configure_fixture(self, root, journal_rc=0):
        core_dir = root / "cores"
        core_dir.mkdir()
        fake_bin = root / "bin"
        fake_bin.mkdir()
        journalctl = fake_bin / "journalctl"
        journalctl.write_text(FAKE_JOURNALCTL, encoding="utf-8")
        journalctl.chmod(0o755)
        env = {
            **os.environ,
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "JOURNAL_ARGS": str(root / "journal.args"),
            "JOURNAL_RC": str(journal_rc),
            "AZURELINUX_CORE_DIAGNOSTICS": "true",
            "CHECKPOINT_DISABLE": "1",
            "PACKER_NO_COLOR": "1",
        }
        return core_dir, env

    def run_diagnostics(self, core_dir, env):
        return subprocess.run(
            ["bash", str(SCRIPT), "fixture", str(core_dir)],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_reports_matching_files_without_printing_or_removing_contents(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "hack") as tmp:
            root = pathlib.Path(tmp)
            core_dir, env = self.configure_fixture(root)
            (core_dir / ".hidden").mkdir()
            candidates = [
                core_dir / "core",
                core_dir / "core.123",
                core_dir / ".hidden/runtime.core",
            ]
            for candidate in candidates:
                candidate.write_bytes(CORE_CONTENT)
            ordinary = core_dir / "ordinary.log"
            ordinary.write_bytes(CORE_CONTENT)
            (core_dir / "core.directory").mkdir()
            (core_dir / "core.link").symlink_to(ordinary)

            result = self.run_diagnostics(core_dir, env)

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("AZURE-LINUX-CORE-DIAGNOSTICS phase=fixture", result.stdout)
            for candidate in candidates:
                self.assertIn(str(candidate), result.stdout)
                self.assertEqual(CORE_CONTENT, candidate.read_bytes())
            self.assertNotIn(str(ordinary), result.stdout)
            self.assertNotIn(str(core_dir / "core.directory"), result.stdout)
            self.assertNotIn(str(core_dir / "core.link"), result.stdout)
            self.assertNotIn("PRIVATE_CORE_MEMORY", result.stdout + result.stderr)

    def test_reports_empty_directories_and_only_requests_safe_journal_fields(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "hack") as tmp:
            root = pathlib.Path(tmp)
            core_dir, env = self.configure_fixture(root)

            result = self.run_diagnostics(core_dir, env)

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("fixture-process", result.stdout)
            args = (root / "journal.args").read_text(encoding="utf-8").splitlines()
            fields = next(arg for arg in args if arg.startswith("--output-fields="))
            self.assertEqual(JOURNAL_FIELDS, set(fields.split("=", 1)[1].split(",")))
            self.assertIn("--output=json", args)

    def test_surfaces_journal_errors_without_losing_file_metadata(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "hack") as tmp:
            root = pathlib.Path(tmp)
            core_dir, env = self.configure_fixture(root, journal_rc=3)
            candidate = core_dir / "core.123"
            candidate.write_bytes(CORE_CONTENT)

            result = self.run_diagnostics(core_dir, env)

            self.assertEqual(3, result.returncode)
            self.assertIn(str(candidate), result.stdout)
            self.assertIn("fixture journal query failed", result.stderr)
            self.assertEqual(CORE_CONTENT, candidate.read_bytes())

    def test_packer_failure_hook_is_scoped_and_preserves_original_failure(self):
        hook = json.loads(TEMPLATE.read_text(encoding="utf-8"))[
            "error-cleanup-provisioner"
        ]
        self.assertEqual(str(SCRIPT.relative_to(ROOT)), hook["script"])
        self.assertEqual(
            "sudo -n env {{.Vars}} /bin/bash '{{.Path}}' packer-error-cleanup",
            hook["execute_command"],
        )
        for build_name, distribution, version, journal_rc, expect_diagnostics in [
            ("sig-azurelinux-3", "azurelinux", "3", 0, True),
            ("sig-azurelinux-3-gen2", "azurelinux", "3", 0, True),
            ("sig-ubuntu-2404", "ubuntu", "2404", 0, False),
            ("sig-azurelinux-2", "azurelinux", "2", 0, False),
            ("sig-azurelinux-3", "azurelinux", "3", 3, True),
        ]:
            with self.subTest(
                build_name=build_name, journal_rc=journal_rc
            ), tempfile.TemporaryDirectory(
                dir=ROOT / "hack"
            ) as tmp:
                root = pathlib.Path(tmp)
                core_dir, env = self.configure_fixture(root, journal_rc)
                candidate = core_dir / "core.123"
                candidate.write_bytes(CORE_CONTENT)
                command = shlex.join(
                    ["bash", str(SCRIPT), "packer-error-cleanup", str(core_dir)]
                )
                template = {
                    "variables": {
                        "distribution": distribution,
                        "distribution_version": version,
                    },
                    "builders": [
                        {
                            "type": "null",
                            "name": build_name,
                            "communicator": "none",
                        }
                    ],
                    "provisioners": [
                        {
                            "type": "shell-local",
                            "inline": ["echo ORIGINAL_PROVISIONING_FAILURE >&2", "exit 17"],
                        }
                    ],
                    "error-cleanup-provisioner": {
                        "type": "shell-local",
                        "environment_vars": hook["environment_vars"],
                        "inline": [command],
                    },
                }
                fixture = root / "packer.json"
                fixture.write_text(json.dumps(template), encoding="utf-8")

                result = subprocess.run(
                    [PACKER, "build", "-color=false", str(fixture)],
                    cwd=root,
                    env=env,
                    text=True,
                    capture_output=True,
                    check=False,
                )

                output = result.stdout + result.stderr
                self.assertNotEqual(0, result.returncode)
                self.assertIn("ORIGINAL_PROVISIONING_FAILURE", output)
                self.assertEqual(
                    expect_diagnostics, "phase=packer-error-cleanup" in output
                )
                self.assertEqual(expect_diagnostics, str(candidate) in output)
                self.assertNotIn("PRIVATE_CORE_MEMORY", output)
                self.assertEqual(CORE_CONTENT, candidate.read_bytes())
                if journal_rc:
                    self.assertIn("fixture journal query failed", output)


if __name__ == "__main__":
    unittest.main()
