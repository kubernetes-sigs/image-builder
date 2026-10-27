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
import pathlib
import tempfile
import unittest


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

        http_root, directory = self.renderer.autoinstall_dir(values)

        self.assertEqual(self.capi_root / "packer/qemu/linux/ubuntu/http", http_root)
        self.assertEqual(self.capi_root / "packer/qemu/linux/ubuntu/http/24.04", directory)

    def test_autoinstall_profile_wins_over_the_boot_command(self):
        values = {
            "distro_name": "ubuntu",
            "autoinstall_profile": "24.04.immutable",
            "http_directory": "./packer/qemu/linux/ubuntu/http/",
            "boot_command_prefix": "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/24.04/'",
        }

        _, directory = self.renderer.autoinstall_dir(values)

        self.assertEqual(
            self.capi_root / "packer/qemu/linux/ubuntu/http/24.04.immutable", directory
        )

    def test_target_http_directory_overrides_the_template_default(self):
        values = {
            "distro_name": "ubuntu",
            "http_directory": "./packer/maas/linux/ubuntu/http/24.04.arm64",
            "boot_command_prefix": "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---",
        }

        http_root, directory = self.renderer.autoinstall_dir(values)

        self.assertEqual(
            self.capi_root / "packer/maas/linux/ubuntu/http/24.04.arm64", directory
        )
        self.assertEqual(http_root, directory)

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
    def render(self, directory, values):
        return self.renderer.rendered_user_data(directory, values)

    def test_mirror_placeholders_are_replaced(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)

        rendered = self.render(directory, dict(MIRRORS))

        self.assertIn("uri: http://us.archive.ubuntu.com/ubuntu", rendered)
        self.assertIn("uri: http://security.ubuntu.com/ubuntu", rendered)
        self.assertNotIn("$UBUNTU", rendered)

    def test_rendering_starts_from_the_password_substituted_user_data(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)
        (directory / "user-data").write_text(SET_SSH_PASSWORD_OUTPUT, encoding="utf-8")

        rendered = self.render(directory, dict(MIRRORS))

        self.assertIn("passwd: $6$salt$hash", rendered)
        self.assertNotIn("$UBUNTU", rendered)

    def test_unsubstituted_password_placeholder_is_refused(self):
        directory = self.write_profile(
            "packer/qemu/linux/ubuntu/http/24.04",
            MIRROR_TEMPLATE + "        passwd: $ENCRYPTED_SSH_PASSWORD\n",
        )

        with self.assertRaisesRegex(ValueError, r"\$ENCRYPTED_SSH_PASSWORD"):
            self.render(directory, dict(MIRRORS))

    def test_plain_ssh_password_placeholder_is_refused(self):
        directory = self.write_profile(
            "packer/qemu/linux/ubuntu/http/24.04",
            MIRROR_TEMPLATE + "        password: $SSH_PASSWORD\n",
        )

        with self.assertRaisesRegex(ValueError, r"\$SSH_PASSWORD"):
            self.render(directory, dict(MIRRORS))

    def test_missing_mirror_variable_is_an_error(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)

        with self.assertRaisesRegex(ValueError, "ubuntu_security_repo"):
            self.render(directory, {"ubuntu_repo": MIRRORS["ubuntu_repo"]})

    def test_mirror_that_would_break_the_yaml_scalar_is_rejected(self):
        directory = self.write_profile("packer/qemu/linux/ubuntu/http/24.04", MIRROR_TEMPLATE)
        values = dict(MIRRORS)
        values["ubuntu_repo"] = "http://mirror.example.com/ubuntu # trailing"

        with self.assertRaises(ValueError) as raised:
            self.render(directory, values)

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

        rendered = self.renderer.rendered_user_data(directory, values)

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
        (self.directory / "user-data").write_text(SET_SSH_PASSWORD_OUTPUT, encoding="utf-8")
        (self.directory / "meta-data").write_text("", encoding="utf-8")
        self.packer_args = [
            "-var-file=packer/config/common.json",
            "-var-file=packer/qemu/qemu-ubuntu-2404.json",
        ]

    def run_main(self, *extra_args):
        """Run the renderer into a fresh output directory, return (stdout, output dir)."""
        output_dir = pathlib.Path(tempfile.mkdtemp(dir=self.tmp.name))
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.renderer.main(
                [
                    "--packer-template",
                    str(self.template),
                    "--output-dir",
                    str(output_dir),
                    "--",
                    *self.packer_args,
                    *extra_args,
                ]
            )
        self.stderr = stderr.getvalue()
        return stdout.getvalue().strip(), output_dir

    def test_renders_into_a_copy_and_prints_its_path(self):
        printed, output_dir = self.run_main()

        self.assertEqual(str(output_dir / "http"), printed)
        rendered = output_dir / "http/24.04/user-data"
        self.assertIn("uri: http://us.archive.ubuntu.com/ubuntu", rendered.read_text())
        self.assertIn("passwd: $6$salt$hash", rendered.read_text())
        # The rest of the http directory is served too, the templates are not.
        self.assertTrue((output_dir / "http/24.04/meta-data").is_file())
        self.assertFalse((output_dir / "http/24.04/user-data.tmpl").exists())
        # The work tree keeps what set-ssh-password.sh wrote.
        self.assertEqual(
            SET_SSH_PASSWORD_OUTPUT, (self.directory / "user-data").read_text(encoding="utf-8")
        )

    def test_targets_sharing_a_directory_get_separate_copies(self):
        _, first = self.run_main("--var", "ubuntu_repo=http://first.example.com/ubuntu")
        _, second = self.run_main("--var", "ubuntu_repo=http://second.example.com/ubuntu")

        self.assertIn("first.example.com", (first / "http/24.04/user-data").read_text())
        self.assertIn("second.example.com", (second / "http/24.04/user-data").read_text())

    def test_command_line_var_overrides_the_var_files(self):
        _, output_dir = self.run_main("--var", "ubuntu_repo=http://mirror.example.com/ubuntu")

        rendered = (output_dir / "http/24.04/user-data").read_text(encoding="utf-8")
        self.assertIn("uri: http://mirror.example.com/ubuntu", rendered)

    def test_targets_without_autoinstall_print_nothing(self):
        self.write_json("packer/qemu/qemu-flatcar.json", {"distro_name": "flatcar"})
        self.packer_args = ["-var-file=packer/qemu/qemu-flatcar.json"]

        printed, output_dir = self.run_main()

        self.assertEqual("", printed)
        self.assertEqual([], list(output_dir.iterdir()))

    def test_nothing_is_printed_that_could_expose_a_mirror_credential(self):
        printed, _ = self.run_main(
            "--var", "ubuntu_repo=http://user:secret@mirror.example.com/ubuntu"
        )

        self.assertNotIn("secret", printed + self.stderr)
        self.assertIn("user-data", self.stderr)


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
