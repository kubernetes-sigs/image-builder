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


CAPI_DIR = pathlib.Path(__file__).resolve().parents[3]
QEMU_GUEST_LIB = CAPI_DIR / "hack" / "lib" / "qemu-guest.sh"
BOOT_SMOKE = CAPI_DIR / "hack" / "qemu-boot-smoke.sh"


def write_stub(path, body, mode=0o755):
    path.write_text(body, encoding="utf-8")
    path.chmod(mode)
    return path


class ResolveImageTests(unittest.TestCase):
    def resolve(self, argument):
        command = (
            f"set -euo pipefail\n"
            f"source {str(QEMU_GUEST_LIB)!r}\n"
            f'if ! image="$(qemu_guest_resolve_image_path {argument!r})"; then exit 3; fi\n'
            f"printf 'RESOLVED %s\\n' \"$image\"\n"
        )
        return subprocess.run(["bash", "-c", command], text=True, capture_output=True)

    def test_unresolvable_image_stops_the_caller(self):
        # An inner command substitution's status is discarded once the outer
        # command runs, so resolving must not be nested inside abs_path.
        with tempfile.TemporaryDirectory() as tmp:
            result = self.resolve(tmp)

            self.assertEqual(3, result.returncode, result.stderr)
            self.assertNotIn("RESOLVED", result.stdout)
            self.assertIn("expected exactly one", result.stderr)

    def test_missing_image_stops_the_caller(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.resolve(str(pathlib.Path(tmp) / "absent.qcow2"))

            self.assertEqual(3, result.returncode, result.stderr)
            self.assertNotIn("RESOLVED", result.stdout)
            self.assertIn("image does not exist", result.stderr)

    def test_output_directory_resolves_to_its_single_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = pathlib.Path(tmp) / "disk.qcow2"
            image.touch()

            result = self.resolve(tmp)

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(f"RESOLVED {image.resolve()}\n", result.stdout)

    def test_relative_image_resolves_to_an_absolute_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = pathlib.Path(tmp) / "disk.qcow2"
            image.touch()
            command = (
                f"set -euo pipefail\n"
                f"source {str(QEMU_GUEST_LIB)!r}\n"
                f"cd {tmp!r}\n"
                f"qemu_guest_resolve_image_path disk.qcow2\n"
            )
            result = subprocess.run(["bash", "-c", command], text=True, capture_output=True)

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(f"{image.resolve()}\n", result.stdout)

    def test_callers_do_not_nest_resolve_inside_abs_path(self):
        self.assertNotIn(
            'qemu_guest_abs_path "$(qemu_guest_resolve_image',
            BOOT_SMOKE.read_text(encoding="utf-8"),
            "the resolve status must not be discarded",
        )


class ArgumentHandlingTests(unittest.TestCase):
    """A trailing "--" leaves no positional parameters, and bash before 4.4
    treats "${@}" as unset under nounset, which aborts before QEMU starts."""

    def test_boot_smoke_accepts_a_trailing_separator(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            for name in ("qemu-system-x86_64", "qemu-img", "ssh", "scp"):
                write_stub(fake_bin / name, "#!/usr/bin/env bash\nexit 0\n")
            image = tmp_path / "image.qcow2"
            image.touch()

            result = subprocess.run(
                ["bash", str(BOOT_SMOKE), str(image), "--"],
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
        for script in (BOOT_SMOKE, QEMU_GUEST_LIB):
            text = script.read_text(encoding="utf-8")
            self.assertNotIn('=("${@}")', text, f"{script} needs the ${{@+...}} guard")
            self.assertNotIn('in "${@}"', text, f"{script} needs the ${{@+...}} guard")


class SignalHandlingTests(unittest.TestCase):
    def test_interrupts_run_the_exit_cleanup(self):
        text = BOOT_SMOKE.read_text(encoding="utf-8")

        self.assertIn("trap cleanup EXIT", text)
        self.assertIn("trap 'exit 130' INT TERM", text)


if __name__ == "__main__":
    unittest.main()
