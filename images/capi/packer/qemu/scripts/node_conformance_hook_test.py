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
    def test_flatcar_is_explicitly_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            write_stub(fake_bin / "sudo", SUDO_STUB)
            os_release = tmp_path / "os-release"
            os_release.write_text('ID="flatcar"\n', encoding="utf-8")
            results_dir = tmp_path / "results"

            result = subprocess.run(
                ["bash", str(HOOK)],
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "NODE_CONFORMANCE_RESULTS_DIR": str(results_dir),
                    "NODE_CONFORMANCE_OS_RELEASE_FILE": str(os_release),
                },
            )

            self.assertNotEqual(0, result.returncode)
            self.assertIn("not supported on Flatcar", result.stderr)
            self.assertIn("exit_code=1", (results_dir / "summary.env").read_text(encoding="utf-8"))

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

    def test_snapshot_and_restore_helpers_are_gone(self):
        script = HOOK.read_text(encoding="utf-8")

        for removed in (
            "snapshot_node_state",
            "restore_node_state",
            "snapshot_runtime_state",
            "cleanup_cri_runtime_state",
            "cleanup_ctr_runtime_state",
            "restore_service_state",
        ):
            self.assertNotIn(removed, script)


class RunnerTests(unittest.TestCase):
    def source_runner(self, command, env=None):
        return subprocess.run(
            ["bash", "-c", f"source {str(RUNNER)!r}\n{command}"],
            text=True,
            capture_output=True,
            env={**os.environ, **(env or {})},
        )

    def test_missing_summary_is_a_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = pathlib.Path(tmp) / "summary.env"

            result = self.source_runner(f"node_conformance_summary_exit_code {str(missing)!r}")

            self.assertNotEqual(0, result.returncode)
            self.assertIn("missing node conformance summary", result.stderr)

    def test_summary_without_an_exit_code_is_a_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = pathlib.Path(tmp) / "summary.env"
            summary.write_text("skipped=true\n", encoding="utf-8")

            result = self.source_runner(f"node_conformance_summary_exit_code {str(summary)!r}")

            self.assertNotEqual(0, result.returncode)
            self.assertIn("does not report an exit_code", result.stderr)

    def test_summary_exit_code_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = pathlib.Path(tmp) / "summary.env"
            summary.write_text("exit_code=7\n", encoding="utf-8")

            result = self.source_runner(f"node_conformance_summary_exit_code {str(summary)!r}")

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("7\n", result.stdout)

    def test_only_explicitly_set_variables_are_forwarded_to_the_guest(self):
        result = self.source_runner(
            "node_conformance_guest_env /tmp/results",
            {"NODE_CONFORMANCE_FOCUS": r"\[Conformance\]", "NODE_CONFORMANCE_TIMEOUT": ""},
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("NODE_CONFORMANCE_RESULTS_DIR=/tmp/results", result.stdout)
        self.assertIn("NODE_CONFORMANCE_FOCUS=", result.stdout)
        self.assertNotIn("NODE_CONFORMANCE_TIMEOUT", result.stdout)

    def test_flatcar_images_are_rejected_before_boot(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            for name in ("qemu-system-x86_64", "qemu-img", "ssh", "scp"):
                write_stub(fake_bin / name, "#!/usr/bin/env bash\nexit 0\n")
            image = tmp_path / "image.qcow2"
            image.write_text("", encoding="utf-8")

            result = subprocess.run(
                ["bash", str(RUNNER), str(image)],
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "QEMU_IMAGE_OS": "flatcar",
                },
            )

            self.assertNotEqual(0, result.returncode)
            self.assertIn("does not support Flatcar images", result.stderr)

    def test_ci_helper_rejects_flatcar_target(self):
        result = subprocess.run(
            ["bash", str(CI_HELPER)],
            text=True,
            capture_output=True,
            env={
                **os.environ,
                "NODE_CONFORMANCE_TARGET": "build-qemu-flatcar",
                "NODE_CONFORMANCE_ACCELERATOR": "tcg",
            },
        )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("not supported for node conformance", result.stderr)


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
                    # Stop right after argument parsing.
                    "QEMU_IMAGE_OS": "flatcar",
                },
            )

            self.assertNotIn("unbound variable", result.stderr)
            self.assertIn("does not support Flatcar images", result.stderr)

    def test_no_bare_positional_expansion_after_a_shift(self):
        text = RUNNER.read_text(encoding="utf-8")

        self.assertNotIn('=("${@}")', text, "the ${@+...} guard is required")


class OutputDirectoryTests(unittest.TestCase):
    def test_the_caller_supplied_output_directory_is_never_removed(self):
        # NODE_CONFORMANCE_OUTPUT_DIR is caller supplied, so an rm -rf on it
        # would delete whatever the caller pointed at, including a cwd.
        runner = RUNNER.read_text(encoding="utf-8")

        self.assertNotIn('rm -rf "${output_dir}"', runner)
        self.assertIn('mkdir -p "${output_dir}"', runner)
        self.assertIn('run_dir="$(mktemp -d "${output_dir}/', runner)

    def test_results_are_evaluated_from_the_per_run_directory(self):
        runner = RUNNER.read_text(encoding="utf-8")

        self.assertIn('node_conformance_summary_exit_code "${run_dir}/summary.env"', runner)


class SignalHandlingTests(unittest.TestCase):
    def test_interrupts_run_the_exit_cleanup(self):
        text = RUNNER.read_text(encoding="utf-8")

        self.assertIn("trap cleanup EXIT", text)
        self.assertIn("trap 'exit 130' INT TERM", text)


class DownloadHardeningTests(unittest.TestCase):
    def test_downloads_retry_and_are_time_capped(self):
        hook = HOOK.read_text(encoding="utf-8")

        self.assertIn("--retry 3 --retry-delay 5 --retry-connrefused", hook)
        self.assertIn('--max-time "${max_time}"', hook)
        # Every download goes through the hardened helper.
        self.assertEqual(1, hook.count("curl --fail"))


class ImageIsNotModifiedTests(unittest.TestCase):
    def test_packer_template_has_no_node_conformance_provisioners(self):
        template = json.loads(PACKER_TEMPLATE.read_text(encoding="utf-8"))
        serialized = json.dumps(template)

        self.assertNotIn("node_conformance", serialized)
        self.assertNotIn("run-e2e-node-conformance", serialized)

    def test_conformance_runs_on_a_copy_on_write_overlay(self):
        runner = RUNNER.read_text(encoding="utf-8")

        self.assertIn("qemu_guest_create_overlay", runner)
        self.assertIn("qemu_guest_create_overlay", QEMU_GUEST_LIB.read_text(encoding="utf-8"))

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
            "NODE_CONFORMANCE_ETCD_VERSION",
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
