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


CAPI_DIR = pathlib.Path(__file__).resolve().parents[3]
HOOK = CAPI_DIR / "hack" / "run-e2e-node-conformance.sh"
RUNNER = CAPI_DIR / "hack" / "qemu-node-conformance.sh"

SUDO_STUB = '''#!/usr/bin/env bash
# Drop sudo options such as -E, then run the command directly.
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
'''


class ShellTestCase(unittest.TestCase):
    """Runs bash snippets with stub commands from self.bin first on PATH."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.stub("sudo", SUDO_STUB)

    def stub(self, name, body, directory=None):
        path = (directory or self.bin) / name
        path.write_text(body, encoding="utf-8")
        path.chmod(0o755)
        return path

    def bash(self, script, *args, env=None):
        command = ["bash", "-c", script] if not args else ["bash", script, *args]
        return subprocess.run(
            command,
            text=True,
            capture_output=True,
            env={**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", **(env or {})},
        )


class GuestHookTests(ShellTestCase):
    def test_cni_setup_ignores_unrelated_files_and_preserves_network_configs(self):
        for plugin in ("bridge", "host-local", "loopback", "portmap"):
            self.stub(plugin, "#!/bin/sh\nexit 0\n")
        for filename in ("README", "existing.conf", "existing.conflist", "existing.json"):
            with self.subTest(filename=filename):
                conf = pathlib.Path(tempfile.mkdtemp(dir=self.tmp))
                existing = conf / filename
                existing.write_text("existing content")

                result = self.bash(
                    f"source {str(HOOK)!r}\ncni_bin_dir={str(self.bin)!r}\n"
                    f"cni_conf_dir={str(conf)!r}\ncni_data_dir={str(self.tmp / 'data')!r}\n"
                    "ensure_cni_config"
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual("existing content", existing.read_text())
                generated = conf / "10-node-conformance.conflist"
                if filename == "README":
                    config = json.loads(generated.read_text())
                    self.assertEqual(["bridge", "portmap"], [p["type"] for p in config["plugins"]])
                    self.assertEqual("host-local", config["plugins"][0]["ipam"]["type"])
                else:
                    self.assertFalse(generated.exists())

    def run_e2e_node(self, ginkgo_body):
        work_dir = self.tmp / "work"
        work_dir.mkdir()
        (self.tmp / "results").mkdir()
        ginkgo = self.stub("ginkgo", ginkgo_body, self.tmp)
        result = self.bash(
            f"set -euo pipefail\nsource {str(HOOK)!r}\n"
            f"work_dir={str(work_dir)!r}\nresults_dir={str(self.tmp / 'results')!r}\n"
            f"ginkgo_bin={str(ginkgo)!r}\ne2e_node_test={str(self.tmp / 'e2e_node.test')!r}\n"
            "run_e2e_node"
        )
        return result, work_dir

    def test_e2e_node_runs_from_the_work_dir_without_the_container_runtime_flag(self):
        invocation = self.tmp / "invocation.txt"
        result, work_dir = self.run_e2e_node(
            f"#!/usr/bin/env bash\n{{ printf 'pwd=%s\\n' \"$PWD\"; printf 'arg=%s\\n' \"$@\"; }} > {str(invocation)!r}\n"
        )

        self.assertEqual(0, result.returncode, result.stderr)
        recorded = invocation.read_text(encoding="utf-8")
        self.assertIn(f"pwd={work_dir}\n", recorded)
        # e2e_node.test has no --container-runtime flag in 1.33 to 1.35, so
        # passing it makes pflag exit before any spec runs.
        self.assertNotIn("--container-runtime=", recorded)
        self.assertIn("--container-runtime-endpoint=", recorded)
        # Standalone mode never joins the test apiserver, so it is off by default.
        self.assertNotIn("--standalone-mode", recorded)

    def test_e2e_node_propagates_ginkgo_failure_through_tee(self):
        result, _ = self.run_e2e_node("#!/usr/bin/env bash\nexit 7\n")

        self.assertEqual(7, result.returncode, result.stderr)

    def test_stop_system_kubelet_failure_is_fatal(self):
        self.stub("systemctl", "#!/usr/bin/env bash\n[[ $1 == list-unit-files ]] && exit 0\nexit 19\n")

        result = self.bash(f"source {str(HOOK)!r}\nstop_system_kubelet")

        self.assertEqual(19, result.returncode)

    def test_checksum_file_is_validated(self):
        # dl.k8s.io serves the digest with no trailing newline, which makes
        # bash read report EOF even though it assigned the value.
        checked = self.tmp / "checked.txt"
        self.stub("sha256sum", f"#!/usr/bin/env bash\ncat > {str(checked)!r}\n")
        sha_file = self.tmp / "payload.sha256"
        verify = f"set -euo pipefail\nsource {str(HOOK)!r}\nverify_sha256_file /payload {str(sha_file)!r}"

        sha_file.write_text("a" * 64, encoding="utf-8")
        result = self.bash(verify)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"{'a' * 64}  /payload\n", checked.read_text(encoding="utf-8"))

        sha_file.write_text("not-a-digest\n", encoding="utf-8")
        result = self.bash(verify)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("invalid or unreadable SHA256 file", result.stderr)


class RunnerTests(ShellTestCase):
    def setUp(self):
        super().setUp()
        self.image = self.tmp / "image.qcow2"
        self.image.touch()
        self.key = self.tmp / "key"
        self.key.write_text("key\n", encoding="utf-8")
        self.env = {"QEMU_SSH_PRIVATE_KEY": str(self.key), "QEMU_IMAGE_FORMAT": "raw"}

    def test_only_explicitly_set_variables_are_forwarded_to_the_guest(self):
        result = self.bash(
            f"source {str(RUNNER)!r}\nnode_conformance_guest_env /tmp/results",
            env={"NODE_CONFORMANCE_FOCUS": r"\[Conformance\]", "NODE_CONFORMANCE_TIMEOUT": ""},
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("NODE_CONFORMANCE_RESULTS_DIR=/tmp/results", result.stdout)
        self.assertIn("NODE_CONFORMANCE_FOCUS=", result.stdout)
        self.assertNotIn("NODE_CONFORMANCE_TIMEOUT", result.stdout)

    def test_runner_rejects_flatcar_before_boot_and_accepts_a_trailing_separator(self):
        for name in ("qemu-system-x86_64", "qemu-img", "ssh", "scp"):
            self.stub(name, "#!/usr/bin/env bash\nexit 0\n")

        result = self.bash(
            str(RUNNER), str(self.image), "--", env={**self.env, "QEMU_IMAGE_OS": "flatcar"}
        )

        self.assertNotEqual(0, result.returncode)
        # A trailing "--" leaves no positional parameters, and bash before 4.4
        # treats "${@}" as unset under nounset.
        self.assertNotIn("unbound variable", result.stderr)
        self.assertIn("does not support Flatcar images", result.stderr)

    def test_runner_fails_when_ssh_reports_a_nonzero_hook_status(self):
        result = self.bash(
            f"""
source {str(RUNNER)!r}
qemu_guest_require_command() {{ :; }}
qemu_guest_resolve_image_path() {{ printf '%s\\n' "$1"; }}
qemu_guest_create_overlay() {{ :; }}
qemu_guest_write_seed_iso() {{ :; }}
qemu_guest_start() {{ QEMU_GUEST_PID=1; }}
qemu_guest_wait_for_ssh() {{ :; }}
qemu_guest_scp() {{ if [[ "$1" == guest:* ]]; then mkdir -p "$2"; touch "$2/e2e_node.log"; fi; }}
qemu_guest_ssh() {{ return 23; }}
qemu_guest_dump_serial_log() {{ :; }}
qemu_guest_stop() {{ :; }}
main {str(self.image)!r}
""",
            env={**self.env, "NODE_CONFORMANCE_OUTPUT_DIR": str(self.tmp / "out")},
        )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ssh status=23", result.stderr)
        # Results are kept even though the run failed.
        self.assertEqual(1, len(list((self.tmp / "out").glob("*/e2e_node.log"))))


if __name__ == "__main__":
    unittest.main()
