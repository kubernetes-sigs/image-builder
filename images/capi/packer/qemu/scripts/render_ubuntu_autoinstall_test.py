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

import contextlib
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).with_name("render_ubuntu_autoinstall.py")
CAPI_DIR = pathlib.Path(__file__).resolve().parents[3]

MIRROR_TEMPLATE = "\n".join(
    [
        "autoinstall:",
        "  apt:",
        "    primary:",
        "      - arches: [default]",
        "        uri: $UBUNTU_REPO",
        "    security:",
        "      - arches: [default]",
        "        uri: $UBUNTU_SECURITY_REPO",
        "",
    ]
)

# What hack/set-ssh-password.sh leaves behind: the same template with the
# password placeholder already substituted.
PASSWORD_LINE = "        passwd: $6$salt$hash\n"
SET_SSH_PASSWORD_OUTPUT = MIRROR_TEMPLATE + PASSWORD_LINE

MIRRORS = {
    "ubuntu_repo": "http://us.archive.ubuntu.com/ubuntu",
    "ubuntu_security_repo": "http://security.ubuntu.com/ubuntu",
}


def load_renderer():
    spec = importlib.util.spec_from_file_location("render_ubuntu_autoinstall", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RendererTestCase(unittest.TestCase):
    def setUp(self):
        self.renderer = load_renderer()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.capi_root = pathlib.Path(self.tmp.name).resolve()
        self.renderer.CAPI_ROOT = self.capi_root
        self.renderer.PACKER_ROOT = self.capi_root / "packer"
        # Do not let a KEEP_RENDERED_AUTOINSTALL from the caller's environment
        # decide what the cleanup tests observe.
        environment = mock.patch.dict(os.environ, {"KEEP_RENDERED_AUTOINSTALL": ""})
        environment.start()
        self.addCleanup(environment.stop)

    def write_json(self, relative_path, payload):
        path = self.capi_root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def write_profile(self, relative_path, content):
        directory = self.capi_root / relative_path
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "user-data.tmpl").write_text(content, encoding="utf-8")
        return directory


class VariablePrecedenceTests(RendererTestCase):
    """Packer resolves legacy JSON template variables in this order:

    template defaults, then every -var-file in command line order, then every
    -var. Verified against `packer validate` on a probe template.
    """

    def setUp(self):
        super().setUp()
        self.template = self.write_json(
            "packer/qemu/packer.json", {"variables": {"ubuntu_repo": "from-template"}}
        )
        self.write_json("packer/config/common.json", {"ubuntu_repo": "from-common"})
        self.write_json("packer/qemu/qemu-ubuntu-2404.json", {"ubuntu_repo": "from-target"})
        self.write_json("overrides.json", {"ubuntu_repo": "from-user-file"})

    def resolve(self, *packer_args):
        return self.renderer.resolve_values(self.template, list(packer_args))

    def test_template_defaults_are_the_lowest_precedence(self):
        self.assertEqual("from-template", self.resolve()["ubuntu_repo"])

    def test_later_var_file_wins(self):
        values = self.resolve(
            "-var-file=packer/config/common.json",
            "-var-file=packer/qemu/qemu-ubuntu-2404.json",
            "-var-file=overrides.json",
        )
        self.assertEqual("from-user-file", values["ubuntu_repo"])

    def test_var_file_order_is_honoured(self):
        values = self.resolve(
            "-var-file=overrides.json",
            "-var-file=packer/config/common.json",
        )
        self.assertEqual("from-common", values["ubuntu_repo"])

    def test_var_outranks_every_var_file_regardless_of_position(self):
        values = self.resolve(
            "--var",
            "ubuntu_repo=from-flag",
            "-var-file=packer/qemu/qemu-ubuntu-2404.json",
            "-var-file=overrides.json",
        )
        self.assertEqual("from-flag", values["ubuntu_repo"])

    def test_last_var_wins(self):
        values = self.resolve("-var=ubuntu_repo=first", "--var", "ubuntu_repo=second")
        self.assertEqual("second", values["ubuntu_repo"])

    def test_parse_packer_args_supports_every_flag_form(self):
        var_files, flag_vars = self.renderer.parse_packer_args(
            [
                "-var-file",
                "a.json",
                '--var-file=b.json',
                "--var",
                "one=1",
                "-var=two=2",
                "-only=qemu",
            ]
        )
        self.assertEqual(["a.json", "b.json"], var_files)
        self.assertEqual({"one": "1", "two": "2"}, flag_vars)


class AutoinstallDirectoryTests(RendererTestCase):
    def test_directory_comes_from_the_boot_command_datasource(self):
        values = {
            "distro_name": "ubuntu",
            "http_directory": "./packer/qemu/linux/{{user `distro_name`}}/http/",
            "boot_command_prefix": (
                "c<wait>linux /casper/vmlinuz --- autoinstall "
                "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/24.04/'<enter>"
            ),
        }

        directory = self.renderer.autoinstall_dir(values)

        self.assertEqual(self.capi_root / "packer/qemu/linux/ubuntu/http/24.04", directory)

    def test_autoinstall_profile_wins_over_the_boot_command(self):
        values = {
            "distro_name": "ubuntu",
            "autoinstall_profile": "24.04.immutable",
            "http_directory": "./packer/qemu/linux/ubuntu/http/",
            "boot_command_prefix": "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/24.04/'",
        }

        directory = self.renderer.autoinstall_dir(values)

        self.assertEqual(
            self.capi_root / "packer/qemu/linux/ubuntu/http/24.04.immutable", directory
        )

    def test_target_http_directory_overrides_the_template_default(self):
        values = {
            "distro_name": "ubuntu",
            "http_directory": "./packer/maas/linux/ubuntu/http/24.04.arm64",
            "boot_command_prefix": "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---",
        }

        directory = self.renderer.autoinstall_dir(values)

        self.assertEqual(
            self.capi_root / "packer/maas/linux/ubuntu/http/24.04.arm64", directory
        )

    def test_non_ubuntu_targets_are_skipped(self):
        values = {
            "distro_name": "flatcar",
            "http_directory": "./packer/files/flatcar/ignition/",
        }

        self.assertIsNone(self.renderer.autoinstall_dir(values))

    def test_directory_outside_packer_is_rejected(self):
        values = {"distro_name": "ubuntu", "http_directory": "../../etc"}

        with self.assertRaisesRegex(ValueError, "outside"):
            self.renderer.autoinstall_dir(values)


class MirrorRenderingTests(RendererTestCase):
    def test_mirror_placeholders_are_replaced(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)

        self.renderer.render_user_data(directory, dict(MIRRORS))

        rendered = (directory / "user-data").read_text(encoding="utf-8")
        self.assertIn("uri: http://us.archive.ubuntu.com/ubuntu", rendered)
        self.assertIn("uri: http://security.ubuntu.com/ubuntu", rendered)
        self.assertNotIn("$UBUNTU", rendered)

    def test_rendering_starts_from_the_password_substituted_user_data(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)
        (directory / "user-data").write_text(SET_SSH_PASSWORD_OUTPUT, encoding="utf-8")

        self.renderer.render_user_data(directory, dict(MIRRORS))

        rendered = (directory / "user-data").read_text(encoding="utf-8")
        self.assertIn("passwd: $6$salt$hash", rendered)
        self.assertNotIn("$UBUNTU", rendered)

    def test_clean_restores_the_password_substituted_user_data(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)
        user_data = directory / "user-data"
        user_data.write_text(SET_SSH_PASSWORD_OUTPUT, encoding="utf-8")

        self.renderer.render_user_data(directory, dict(MIRRORS))
        self.assertEqual(
            SET_SSH_PASSWORD_OUTPUT,
            (directory / "user-data.orig").read_text(encoding="utf-8"),
        )

        self.assertEqual(("Restored", user_data), self.renderer.clean_user_data(directory))

        # set-ssh-password.sh runs once per make invocation, so a target sharing
        # this directory has to find its output here, not a pristine template.
        self.assertEqual(SET_SSH_PASSWORD_OUTPUT, user_data.read_text(encoding="utf-8"))
        self.assertFalse((directory / "user-data.orig").exists())

    def test_second_target_in_the_same_directory_keeps_the_password(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)
        (directory / "user-data").write_text(SET_SSH_PASSWORD_OUTPUT, encoding="utf-8")

        for _ in range(2):
            self.renderer.render_user_data(directory, dict(MIRRORS))
            rendered = (directory / "user-data").read_text(encoding="utf-8")
            self.assertIn("passwd: $6$salt$hash", rendered)
            self.assertIn("uri: http://us.archive.ubuntu.com/ubuntu", rendered)
            self.renderer.clean_user_data(directory)

    def test_render_recovers_a_stash_left_by_an_interrupted_run(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)
        user_data = directory / "user-data"
        # As if a run had been killed after writing the rendered file.
        user_data.write_text(
            SET_SSH_PASSWORD_OUTPUT.replace("$UBUNTU_REPO", "http://stale/ubuntu"),
            encoding="utf-8",
        )
        (directory / "user-data.orig").write_text(SET_SSH_PASSWORD_OUTPUT, encoding="utf-8")

        self.renderer.render_user_data(directory, dict(MIRRORS))
        self.renderer.clean_user_data(directory)

        self.assertEqual(SET_SSH_PASSWORD_OUTPUT, user_data.read_text(encoding="utf-8"))

    def test_unsubstituted_password_placeholder_is_refused(self):
        directory = self.write_profile(
            "packer/qemu/linux/ubuntu/http/24.04",
            MIRROR_TEMPLATE + "        passwd: $ENCRYPTED_SSH_PASSWORD\n",
        )

        with self.assertRaisesRegex(ValueError, r"\$ENCRYPTED_SSH_PASSWORD"):
            self.renderer.render_user_data(directory, dict(MIRRORS))

        # Nothing was written, so no half-rendered file is left for Packer.
        self.assertFalse((directory / "user-data").exists())

    def test_plain_ssh_password_placeholder_is_refused(self):
        directory = self.write_profile(
            "packer/qemu/linux/ubuntu/http/24.04",
            MIRROR_TEMPLATE + "        password: $SSH_PASSWORD\n",
        )

        with self.assertRaisesRegex(ValueError, r"\$SSH_PASSWORD"):
            self.renderer.render_user_data(directory, dict(MIRRORS))

    def test_missing_mirror_variable_is_an_error(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)

        with self.assertRaisesRegex(ValueError, "ubuntu_security_repo"):
            self.renderer.render_user_data(directory, {"ubuntu_repo": MIRRORS["ubuntu_repo"]})

    def test_mirror_that_would_break_the_yaml_scalar_is_rejected(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)
        values = dict(MIRRORS)
        values["ubuntu_repo"] = "http://mirror.example.com/ubuntu # trailing"

        with self.assertRaises(ValueError) as raised:
            self.renderer.render_user_data(directory, values)

        # The message names the variable, never the value: it can hold a password.
        self.assertIn("ubuntu_repo", str(raised.exception))
        self.assertNotIn("mirror.example.com", str(raised.exception))


class ImmutableRenderingTests(RendererTestCase):
    def test_immutable_placeholders_are_applied(self):
        directory = self.write_profile(
            "packer/qemu/linux/ubuntu/http/24.04.immutable",
            "\n".join(
                [
                    "storage:",
                    "  config:",
                    "    - id: partition-root",
                    "      size: ${IMMUTABLE_AUTOINSTALL_ROOT_PARTITION_SIZE}",
                    "${IMMUTABLE_AUTOINSTALL_DATA_PARTITION_CONFIG}",
                    "",
                ]
            ),
        )
        values = dict(self.renderer.IMMUTABLE_DEFAULTS)
        values.update(
            {
                "immutable_data_partition": "true",
                "immutable_data_partition_mount": "/var/lib/cluster-api-data",
            }
        )

        self.renderer.render_user_data(directory, values)

        rendered = (directory / "user-data").read_text(encoding="utf-8")
        self.assertIn("size: 12884901888", rendered)
        self.assertIn("label: CAPI-DATA", rendered)
        self.assertIn("path: /var/lib/cluster-api-data", rendered)
        self.assertNotIn("${IMMUTABLE_AUTOINSTALL", rendered)

    def test_data_partition_config_is_empty_when_disabled(self):
        values = dict(self.renderer.IMMUTABLE_DEFAULTS)

        self.assertEqual("", self.renderer.data_partition_config(values))

    def test_data_partition_config_renders_labeled_ext4_mount(self):
        values = dict(self.renderer.IMMUTABLE_DEFAULTS)
        values.update(
            {
                "immutable_data_partition": "true",
                "immutable_data_partition_label": "RUNTIME-DATA",
                "immutable_data_partition_mount": "/runtime-data",
                "immutable_data_partition_fstype": "ext4",
            }
        )

        rendered = self.renderer.data_partition_config(values)

        self.assertIn("id: partition-data", rendered)
        self.assertIn("size: -1", rendered)
        self.assertIn("label: RUNTIME-DATA", rendered)
        self.assertIn("path: /runtime-data", rendered)

    def test_data_partition_config_rejects_unsupported_values(self):
        values = dict(self.renderer.IMMUTABLE_DEFAULTS)
        values["immutable_data_partition"] = "true"

        values["immutable_data_partition_label"] = "label-with-more-than-sixteen-chars"
        with self.assertRaisesRegex(ValueError, "immutable_data_partition_label"):
            self.renderer.data_partition_config(values)

        values = dict(self.renderer.IMMUTABLE_DEFAULTS)
        values["immutable_data_partition"] = "true"
        values["immutable_data_partition_mount"] = "/"
        with self.assertRaisesRegex(ValueError, "immutable_data_partition_mount"):
            self.renderer.data_partition_config(values)

        values = dict(self.renderer.IMMUTABLE_DEFAULTS)
        values["immutable_data_partition"] = "true"
        values["immutable_data_partition_fstype"] = "xfs"
        with self.assertRaisesRegex(ValueError, "currently supports only ext4"):
            self.renderer.data_partition_config(values)


class MainTests(RendererTestCase):
    def setUp(self):
        super().setUp()
        self.template = self.write_json(
            "packer/qemu/packer.json",
            {"variables": {"http_directory": "./packer/qemu/linux/{{user `distro_name`}}/http/"}},
        )
        self.write_json(
            "packer/config/common.json",
            {
                "ubuntu_repo": "http://us.archive.ubuntu.com/ubuntu",
                "ubuntu_security_repo": "http://security.ubuntu.com/ubuntu",
            },
        )
        self.write_json(
            "packer/qemu/qemu-ubuntu-2404.json",
            {
                "distro_name": "ubuntu",
                "boot_command_prefix": (
                    "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/24.04/'"
                ),
            },
        )
        self.directory = self.write_profile(
            "packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE
        )
        self.packer_args = [
            "-var-file=packer/config/common.json",
            "-var-file=packer/qemu/qemu-ubuntu-2404.json",
        ]

    def run_main(self, *extra):
        # The renderer's progress lines would otherwise land in the output of
        # `make test-qemu-immutable`.
        with contextlib.redirect_stdout(io.StringIO()):
            self.renderer.main(
                ["--packer-template", str(self.template), *extra, "--", *self.packer_args]
            )

    def test_only_the_selected_target_is_rendered(self):
        other = self.write_profile("packer/qemu/linux/ubuntu/http/26.04", MIRROR_TEMPLATE)

        self.run_main()

        self.assertIn("us.archive.ubuntu.com", (self.directory / "user-data").read_text())
        self.assertFalse((other / "user-data").exists())

    def test_command_line_var_overrides_the_var_files(self):
        self.packer_args += ["--var", "ubuntu_repo=http://mirror.example.com/ubuntu"]

        self.run_main()

        rendered = (self.directory / "user-data").read_text(encoding="utf-8")
        self.assertIn("uri: http://mirror.example.com/ubuntu", rendered)

    def test_clean_removes_the_rendered_user_data(self):
        self.run_main()
        self.assertTrue((self.directory / "user-data").exists())

        self.run_main("--clean")

        self.assertFalse((self.directory / "user-data").exists())
        self.assertTrue((self.directory / "user-data.tmpl").exists())

    def test_clean_keeps_the_rendered_user_data_on_request(self):
        self.run_main()

        with mock.patch.dict(os.environ, {"KEEP_RENDERED_AUTOINSTALL": "1"}):
            self.run_main("--clean")

        self.assertTrue((self.directory / "user-data").exists())

    def test_nothing_is_printed_that_could_expose_a_mirror_credential(self):
        self.packer_args += ["--var", "ubuntu_repo=http://user:pass@mirror.example.com/ubuntu"]

        with mock.patch("builtins.print") as printed:
            self.run_main()

        output = " ".join(str(call.args[0]) for call in printed.call_args_list)
        self.assertNotIn("pass", output)
        self.assertIn("user-data", output)


class RepositoryTemplateTests(unittest.TestCase):
    """Checks against the templates as they are checked in."""

    def profile(self, *parts):
        return (CAPI_DIR / "packer").joinpath(*parts) / "user-data.tmpl"

    def test_active_ubuntu_autoinstall_templates_use_the_mirror_variables(self):
        profiles = [
            ("qemu", "linux/ubuntu/http/24.04"),
            ("qemu", "linux/ubuntu/http/24.04.efi"),
            ("qemu", "linux/ubuntu/http/24.04.immutable"),
            ("qemu", "linux/ubuntu/http/26.04"),
            ("qemu", "linux/ubuntu/http/26.04.efi"),
            ("maas", "linux/ubuntu/http/24.04.arm64"),
            ("proxmox", "linux/ubuntu/http/24.04"),
            ("proxmox", "linux/ubuntu/http/26.04"),
        ]
        for platform, profile in profiles:
            with self.subTest(profile=f"{platform}/{profile}"):
                template = self.profile(platform, profile).read_text(encoding="utf-8")
                self.assertIn("uri: $UBUNTU_REPO", template)
                self.assertIn("uri: $UBUNTU_SECURITY_REPO", template)

    def test_immutable_template_runs_cleanup_in_target(self):
        template = self.profile("qemu", "linux/ubuntu/http/24.04.immutable").read_text(
            encoding="utf-8"
        )

        self.assertIn("curtin in-target --target=/target -- swapoff -a", template)
        self.assertIn("curtin in-target --target=/target -- apt-get clean", template)
        self.assertNotIn("    - swapoff -a\n", template)


if __name__ == "__main__":
    unittest.main()
