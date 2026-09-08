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
import re
import subprocess
import tempfile
import unittest


CAPI_DIR = pathlib.Path(__file__).resolve().parents[3]
REPO_ROOT = pathlib.Path(__file__).resolve().parents[5]
HOOK = CAPI_DIR / "hack" / "run-e2e-node-conformance.sh"
RUNNER = CAPI_DIR / "hack" / "qemu-node-conformance.sh"
BOOT_SMOKE = CAPI_DIR / "hack" / "qemu-boot-smoke.sh"
QEMU_GUEST_LIB = CAPI_DIR / "hack" / "lib" / "qemu-guest.sh"
CI_HELPER = CAPI_DIR / "scripts" / "ci-qemu-node-conformance.sh"
PACKER_TEMPLATE = CAPI_DIR / "packer" / "qemu" / "packer.json.tmpl"
DOC = REPO_ROOT / "docs" / "book" / "src" / "capi" / "node-conformance.md"

SUDO_STUB = '''#!/usr/bin/env bash
# Drop sudo options such as -E, then run the command directly.
while [[ "${1:-}" == -* ]]; do shift; done
exec "$@"
'''


def write_stub(path, body, mode=0o755):
    path.write_text(body, encoding="utf-8")
    path.chmod(mode)
    return path


def shell_default(script_text, name):
    """Returns the literal default of a "${NAME:-DEFAULT}" expansion.

    The expansions live inside double quotes, so bash collapses a doubled
    backslash into a single one before the value is used.
    """
    match = re.search(r'\$\{' + re.escape(name) + r':-(.*?)\}"', script_text)
    if match is None:
        raise AssertionError(f"no default found for {name}")
    return match.group(1).replace("\\\\", "\\")


def documented_defaults():
    defaults = {}
    for line in DOC.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\| `([A-Z_]+)` \| `(.*?)` \| ", line)
        if match:
            defaults[match.group(1)] = match.group(2).replace("\\|", "|")
    return defaults


class GuestHookTests(unittest.TestCase):
    def test_e2e_node_runs_from_the_work_dir_without_the_container_runtime_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            write_stub(fake_bin / "sudo", SUDO_STUB)

            work_dir = tmp_path / "work"
            results_dir = tmp_path / "results"
            work_dir.mkdir()
            results_dir.mkdir()
            invocation = tmp_path / "invocation.txt"
            ginkgo = write_stub(
                tmp_path / "ginkgo",
                f"""#!/usr/bin/env bash
{{
  printf 'pwd=%s\\n' "$PWD"
  printf 'arg=%s\\n' "$@"
}} > {str(invocation)!r}
""",
            )

            command = f"""
set -euo pipefail
source {str(HOOK)!r}
work_dir={str(work_dir)!r}
results_dir={str(results_dir)!r}
ginkgo_bin={str(ginkgo)!r}
e2e_node_test={str(tmp_path / 'e2e_node.test')!r}
run_e2e_node unix:///run/containerd/containerd.sock /usr/bin/containerd
"""
            result = subprocess.run(
                ["bash", "-c", command],
                text=True,
                capture_output=True,
                env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"},
            )

            self.assertEqual(0, result.returncode, result.stderr)
            recorded = invocation.read_text(encoding="utf-8")
            self.assertIn(f"pwd={work_dir}\n", recorded)
            # e2e_node.test has no --container-runtime flag in 1.33 to 1.35, so
            # passing it makes pflag exit before any spec runs.
            self.assertNotIn("--container-runtime=", recorded)
            self.assertIn("--container-runtime-endpoint=", recorded)
            # Standalone mode never joins the test apiserver, so it is off by
            # default and must not be requested here.
            self.assertNotIn("--standalone-mode", recorded)

    def test_e2e_node_propagates_ginkgo_failure_through_tee(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            write_stub(fake_bin / "sudo", SUDO_STUB)
            work_dir = tmp_path / "work"
            results_dir = tmp_path / "results"
            work_dir.mkdir()
            results_dir.mkdir()
            ginkgo = write_stub(tmp_path / "ginkgo", "#!/usr/bin/env bash\nexit 7\n")

            command = f"""
set -euo pipefail
source {str(HOOK)!r}
work_dir={str(work_dir)!r}
results_dir={str(results_dir)!r}
ginkgo_bin={str(ginkgo)!r}
e2e_node_test={str(tmp_path / 'e2e_node.test')!r}
run_e2e_node unix:///run/containerd/containerd.sock /usr/bin/containerd
"""
            result = subprocess.run(
                ["bash", "-c", command],
                text=True,
                capture_output=True,
                env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"},
            )

            self.assertEqual(7, result.returncode, result.stderr)

    def test_stop_system_kubelet_failure_is_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            write_stub(fake_bin / "sudo", SUDO_STUB)
            write_stub(
                fake_bin / "systemctl",
                "#!/usr/bin/env bash\n[[ $1 == list-unit-files ]] && exit 0\nexit 19\n",
            )
            result = subprocess.run(
                ["bash", "-c", f"source {str(HOOK)!r}\nstop_system_kubelet"],
                text=True,
                capture_output=True,
                env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"},
            )
            self.assertEqual(19, result.returncode)

    def test_checksum_without_a_trailing_newline_is_accepted(self):
        # dl.k8s.io serves the digest with no trailing newline, which makes
        # bash read report EOF even though it assigned the value.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            checked = tmp_path / "checked.txt"
            write_stub(
                fake_bin / "sha256sum",
                f"""#!/usr/bin/env bash
cat > {str(checked)!r}
""",
            )
            payload = tmp_path / "kubernetes-test.tar.gz"
            payload.write_text("payload", encoding="utf-8")
            digest = "a" * 64
            sha_file = tmp_path / "kubernetes-test.tar.gz.sha256"
            sha_file.write_text(digest, encoding="utf-8")

            command = f"""
set -euo pipefail
source {str(HOOK)!r}
verify_sha256_file {str(payload)!r} {str(sha_file)!r}
"""
            result = subprocess.run(
                ["bash", "-c", command],
                text=True,
                capture_output=True,
                env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"},
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(f"{digest}  {payload}\n", checked.read_text(encoding="utf-8"))

    def test_invalid_checksum_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            sha_file = pathlib.Path(tmp) / "sha256"
            sha_file.write_text("not-a-digest\n", encoding="utf-8")

            result = subprocess.run(
                ["bash", "-c", f"source {str(HOOK)!r}\nverify_sha256_file /dev/null {str(sha_file)!r}"],
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(0, result.returncode)
            self.assertIn("invalid or unreadable SHA256 file", result.stderr)

    def test_standalone_mode_is_opt_in(self):
        self.assertEqual("false", shell_default(HOOK.read_text(encoding="utf-8"),
                                                "NODE_CONFORMANCE_STANDALONE_MODE"))

class RunnerTests(unittest.TestCase):
    def source_runner(self, command, env=None):
        return subprocess.run(
            ["bash", "-c", f"source {str(RUNNER)!r}\n{command}"],
            text=True,
            capture_output=True,
            env={**os.environ, **(env or {})},
        )

    def test_only_explicitly_set_variables_are_forwarded_to_the_guest(self):
        result = self.source_runner(
            "node_conformance_guest_env /tmp/results",
            {"NODE_CONFORMANCE_FOCUS": r"\[Conformance\]", "NODE_CONFORMANCE_TIMEOUT": ""},
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("NODE_CONFORMANCE_RESULTS_DIR=/tmp/results", result.stdout)
        self.assertIn("NODE_CONFORMANCE_FOCUS=", result.stdout)
        self.assertNotIn("NODE_CONFORMANCE_TIMEOUT", result.stdout)

    def test_runner_rejects_flatcar_before_boot(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            for name in ("qemu-system-x86_64", "qemu-img", "ssh", "scp"):
                write_stub(fake_bin / name, "#!/usr/bin/env bash\nexit 0\n")
            image = tmp_path / "image.qcow2"
            image.touch()
            key = tmp_path / "key"
            key.write_text("key\n", encoding="utf-8")

            result = subprocess.run(
                ["bash", str(RUNNER), str(image), "--"],
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "QEMU_IMAGE_FORMAT": "raw",
                    "QEMU_IMAGE_OS": "flatcar",
                    "QEMU_SSH_PRIVATE_KEY": str(key),
                },
            )
            self.assertNotEqual(0, result.returncode)
            self.assertIn("does not support Flatcar images", result.stderr)

    def test_runner_fails_when_ssh_reports_a_nonzero_hook_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            image = tmp_path / "image.qcow2"
            image.touch()
            key = tmp_path / "key"
            key.write_text("key\n", encoding="utf-8")
            command = f"""
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
main {str(image)!r}
"""
            result = subprocess.run(
                ["bash", "-c", command],
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    "QEMU_SSH_PRIVATE_KEY": str(key),
                    "QEMU_IMAGE_FORMAT": "raw",
                    "NODE_CONFORMANCE_RESULTS_DIR": "/tmp/node-results",
                },
            )
            self.assertNotEqual(0, result.returncode)
            self.assertIn("ssh status=23", result.stderr)

class ArgumentHandlingTests(unittest.TestCase):
    def test_conformance_runner_accepts_a_trailing_separator(self):
        # A trailing "--" leaves no positional parameters, and bash before 4.4
        # treats "${@}" as unset under nounset, aborting before QEMU starts.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            for name in ("qemu-system-x86_64", "qemu-img", "ssh", "scp"):
                write_stub(fake_bin / name, "#!/usr/bin/env bash\nexit 0\n")
            image = tmp_path / "image.qcow2"
            image.touch()

            result = subprocess.run(
                ["bash", str(RUNNER), str(image), "--"],
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    # Stop after argument parsing and image format detection.
                    "QEMU_IMAGE_FORMAT": "raw",
                },
            )

            self.assertNotIn("unbound variable", result.stderr)

class ImageIsNotModifiedTests(unittest.TestCase):
    def test_packer_template_has_no_node_conformance_provisioners(self):
        template = json.loads(PACKER_TEMPLATE.read_text(encoding="utf-8"))
        serialized = json.dumps(template)

        self.assertNotIn("node_conformance", serialized)
        self.assertNotIn("run-e2e-node-conformance", serialized)

    def test_boot_smoke_and_conformance_share_the_qemu_guest_library(self):
        for script in (RUNNER, BOOT_SMOKE):
            self.assertIn(
                'source "${script_dir}/lib/qemu-guest.sh"',
                script.read_text(encoding="utf-8"),
                f"{script} should reuse the shared QEMU guest helpers",
            )


class DocumentationTests(unittest.TestCase):
    def test_documented_hook_defaults_match_the_script(self):
        script = HOOK.read_text(encoding="utf-8")
        documented = documented_defaults()

        for name in (
            "NODE_CONFORMANCE_FOCUS",
            "NODE_CONFORMANCE_SKIP",
            "NODE_CONFORMANCE_PARALLELISM",
            "NODE_CONFORMANCE_FLAKE_ATTEMPTS",
            "NODE_CONFORMANCE_TIMEOUT",
            "NODE_CONFORMANCE_STANDALONE_MODE",
            "NODE_CONFORMANCE_KUBELET_FLAGS",
            "NODE_CONFORMANCE_DOWNLOAD_TIMEOUT",
            "NODE_CONFORMANCE_RESULTS_DIR",
        ):
            self.assertIn(name, documented)
            self.assertEqual(shell_default(script, name), documented[name], name)

    def test_documented_runner_defaults_match_the_script(self):
        script = RUNNER.read_text(encoding="utf-8")
        documented = documented_defaults()

        for name in ("QEMU_CPUS", "QEMU_MEMORY", "QEMU_SSH_TIMEOUT"):
            self.assertIn(name, documented)
            self.assertEqual(shell_default(script, name), documented[name], name)


if __name__ == "__main__":
    unittest.main()
