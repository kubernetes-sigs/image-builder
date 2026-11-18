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
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


WORKFLOW = Path(__file__).resolve().parents[3] / ".github/workflows/build-azure-sig.yaml"
MANAGED_IMAGE_ID = "/subscriptions/test/resourceGroups/images/providers/Microsoft.Compute/images/test"
FAKE_AZ = r"""
import json
import os
from pathlib import Path
import sys

Path(os.environ["AZURE_ARGS"]).write_text(json.dumps(sys.argv[1:]), encoding="utf-8")
if os.environ.get("AZURE_FAILURE"):
    sys.exit("managed image lookup failed")
print(os.environ["IMAGE_GENERATION"])
"""


class AzureSIGPublishingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        step = workflow.split("      - name: Generate SIG publishing info\n", 1)[1]
        step = step.split("\n      - name:", 1)[0]
        cls.script = textwrap.dedent(step.split("        run: |\n", 1)[1])

    def run_publishing(self, image_name, generation, failure=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            azure = root / "packer/azure"
            azure.mkdir(parents=True)
            (azure / "packer.out").write_text(
                "\n".join(
                    [
                        "OSType: Windows",
                        f"ManagedImageId: {MANAGED_IMAGE_ID}",
                        f"SharedImageGalleryImageName: {image_name}",
                        "SharedImageGalleryImageVersion: 1.36.1",
                    ]
                ) + "\n",
                encoding="utf-8",
            )
            (azure / "tags.out").write_text("test=true", encoding="utf-8")
            fake_bin = root / "bin"
            fake_bin.mkdir()
            az = fake_bin / "az"
            az.write_text(f"#!{sys.executable}\n" + FAKE_AZ, encoding="utf-8")
            az.chmod(0o755)
            env = {
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "DISTRO": "windows-2025-containerd-gen2",
                "IMAGE_GENERATION": generation,
                "AZURE_ARGS": str(root / "azure-args.json"),
                "AZURE_FAILURE": "1" if failure else "",
            }
            result = subprocess.run(
                ["bash", "-c", self.script],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
                check=False,
            )
            artifact = azure / "sig-publishing-info.json"
            info = json.loads(artifact.read_text()) if artifact.exists() else None
            args_path = root / "azure-args.json"
            args = json.loads(args_path.read_text()) if args_path.exists() else []
            return result, info, args

    def test_generation_comes_from_managed_image_not_its_name(self):
        for image_name, generation in [
            ("capi-windows-2025-gen2-containerd", "V2"),
            ("capi-windows-2022-cvm-containerd", "V2"),
            ("capi-ubuntu-2404-gen2", "V2"),
            ("capi-windows-2025-containerd", "V1"),
            ("capi-ubuntu-2404", "V1"),
            ("custom-image", "V2"),
            ("custom-image-gen2", "V1"),
        ]:
            with self.subTest(image_name=image_name, generation=generation):
                result, info, args = self.run_publishing(image_name, generation)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertEqual(generation, info["hyperv_gen"])
                self.assertEqual(image_name, info["shared_image_gallery_image_name"])
                self.assertEqual(MANAGED_IMAGE_ID, info["managed_image_id"])
                self.assertEqual(
                    [
                        "image", "show", "--ids", MANAGED_IMAGE_ID,
                        "--query", "hyperVGeneration", "--output", "tsv",
                    ],
                    args,
                )

    def test_missing_or_unexpected_generation_prevents_publishing_artifact(self):
        for generation in ("", "null", "V3"):
            with self.subTest(generation=generation):
                result, info, _ = self.run_publishing("custom-image", generation)
                self.assertNotEqual(0, result.returncode)
                self.assertIn("::error::Unexpected Hyper-V generation", result.stdout)
                self.assertIsNone(info)

    def test_azure_lookup_failure_is_not_replaced_with_a_default_generation(self):
        result, info, _ = self.run_publishing("custom-image-gen2", "V2", failure=True)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("managed image lookup failed", result.stderr)
        self.assertIsNone(info)


if __name__ == "__main__":
    unittest.main()
