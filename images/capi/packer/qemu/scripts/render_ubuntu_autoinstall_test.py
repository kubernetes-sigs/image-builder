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

import importlib.util
import json
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("render_ubuntu_autoinstall.py")


def load_renderer():
    spec = importlib.util.spec_from_file_location("render_ubuntu_autoinstall", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RenderUbuntuAutoinstallTests(unittest.TestCase):
    def setUp(self):
        self.renderer = load_renderer()

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

    def test_render_user_data_applies_immutable_placeholders(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / "packer"
            profile_dir = root / "qemu" / "linux" / "ubuntu" / "http" / "24.04.immutable"
            profile_dir.mkdir(parents=True)
            (profile_dir / "user-data.tmpl").write_text(
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
                encoding="utf-8",
            )
            var_file = pathlib.Path(tmp) / "qemu-ubuntu-2404-immutable.json"
            var_file.write_text(
                json.dumps(
                    {
                        "autoinstall_profile": "24.04.immutable",
                        "distro_name": "ubuntu",
                        "immutable_data_partition": "true",
                        "immutable_data_partition_label": "CAPI-DATA",
                        "immutable_data_partition_mount": "/var/lib/cluster-api-data",
                        "immutable_root_partition_size": "12884901888",
                    }
                ),
                encoding="utf-8",
            )
            self.renderer.ROOT = root

            values = dict(self.renderer.IMMUTABLE_DEFAULTS)
            values.update(self.renderer.load_json(var_file))
            self.renderer.render_user_data(var_file, values)

            rendered = (profile_dir / "user-data").read_text(encoding="utf-8")
            self.assertIn("size: 12884901888", rendered)
            self.assertIn("label: CAPI-DATA", rendered)
            self.assertIn("path: /var/lib/cluster-api-data", rendered)
            self.assertNotIn("${IMMUTABLE_AUTOINSTALL", rendered)

    def test_parse_packer_flags_supports_var_and_var_file_forms(self):
        values, var_files = self.renderer.parse_packer_flags(
            "--var immutable_data_partition_label=RUNTIME-DATA "
            "--var='immutable_data_partition_mount=/runtime-data' "
            "--var-file overrides.json"
        )

        self.assertEqual("RUNTIME-DATA", values["immutable_data_partition_label"])
        self.assertEqual("/runtime-data", values["immutable_data_partition_mount"])
        self.assertEqual(["overrides.json"], var_files)

    def test_immutable_template_runs_cleanup_in_target(self):
        template = (
            pathlib.Path(__file__).resolve().parents[1]
            / "linux"
            / "ubuntu"
            / "http"
            / "24.04.immutable"
            / "user-data.tmpl"
        ).read_text(encoding="utf-8")

        self.assertIn("curtin in-target --target=/target -- swapoff -a", template)
        self.assertIn("curtin in-target --target=/target -- apt-get clean", template)
        self.assertNotIn("    - swapoff -a\n", template)


if __name__ == "__main__":
    unittest.main()
