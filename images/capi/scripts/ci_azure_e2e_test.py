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

"""Exercise Azure CI orchestration with fake Azure CLI and image builds."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent
TARGETS = ("ubuntu-2204", "ubuntu-2404-cvm")
FAKE_COMMAND = r'''
import json
import os
from pathlib import Path
import sys
import time
import uuid

command = Path(sys.argv[0]).name
args = sys.argv[1:]
config = Path(os.environ.get("AZURE_CONFIG_DIR", os.environ["HOME"] + "/.azure"))
session = config / "session"
event = dict(command=command, args=args, config=str(config),
             location=os.environ.get("AZURE_LOCATION"),
             cli_auth=os.environ.get("USE_AZURE_CLI_AUTH"))
with open(os.environ["TEST_EVENTS"], "a", encoding="utf-8") as log:
    log.write(json.dumps(event) + "\n")

if command == "az" and args[0] == "login":
    if config.name == os.environ.get("TEST_LOGIN_FAILURE"):
        sys.exit("simulated login failure")
    config.mkdir(parents=True, exist_ok=True)
    session.write_text(str(uuid.uuid4()), encoding="utf-8")
elif command == "az" and args[:3] == ["vm", "image", "show"]:
    assert session.exists(), "image lookup before login"
    print("1234.0.0")
elif command == "az" and args[:2] == ["group", "delete"]:
    pass
elif command == "make" and args == ["build-azure-sigs", "--recon", "-d"]:
    for target in ("ubuntu-2204", "ubuntu-2404-cvm"):
        print("Must remake target 'build-azure-sig-" + target + "'.")
elif command == "make" and args == ["deps-azure"]:
    pass
elif command == "make" and len(args) == 1 and args[0].startswith("build-azure-sig-"):
    target = args[0].removeprefix("build-azure-sig-")
    assert session.exists(), "build before login"
    before = session.read_text(encoding="utf-8")
    if not os.environ.get("TEST_LOGIN_FAILURE"):
        # Keep both builds alive together to exercise the parallel orchestration.
        ready = Path(os.environ["TEST_READY"])
        (ready / target).touch()
        deadline = time.monotonic() + 10
        while len(list(ready.iterdir())) < 2:
            assert time.monotonic() < deadline, "builds did not run concurrently"
            time.sleep(0.01)
    assert session.read_text(encoding="utf-8") == before, "login replaced an active session"
    if target == os.environ.get("TEST_BUILD_FAILURE"):
        sys.exit("simulated build failure")
else:
    sys.exit("unexpected command: " + repr(sys.argv))
'''


class AzureCITest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["bash", "-c", "(( BASH_VERSINFO[0] >= 4 ))"], check=False,
        )
        if result.returncode:
            raise RuntimeError("Azure CI tests require Bash 4 or newer on PATH")

    def run_ci(self, federated=True, custom_config=False, **overrides):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copy2(SCRIPT_DIR / "ci-azure-e2e.sh", scripts)
            creds = root / "packer/azure/scripts"
            creds.mkdir(parents=True)
            shutil.copy2(SCRIPT_DIR.parent / "packer/azure/scripts/parse-prow-creds.sh", creds)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            for command in ("az", "make"):
                stub = fake_bin / command
                stub.write_text(f"#!{sys.executable}\n" + FAKE_COMMAND, encoding="utf-8")
                stub.chmod(0o755)
            (root / "ready").mkdir()
            env = {
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "HOME": str(root),
                "ARTIFACTS": str(root / "artifacts"),
                "PYTHON_BIN_DIR": str(fake_bin),
                "AZURE_CLIENT_ID": "test-client",
                "AZURE_TENANT_ID": "test-tenant",
                "AZURE_SUBSCRIPTION_ID": "test-subscription",
                "AZURE_LOCATION": "uksouth",
                "TEST_EVENTS": str(root / "events.jsonl"),
                "TEST_READY": str(root / "ready"),
                **overrides,
            }
            if federated:
                token = root / "federated token"
                token.write_text("test-token", encoding="utf-8")
                env["AZURE_FEDERATED_TOKEN_FILE"] = str(token)
            else:
                env["AZURE_CLIENT_SECRET"] = "test-secret"
            if custom_config:
                env["AZURE_CONFIG_DIR"] = str(root / "custom config")
            result = subprocess.run(
                ["bash", str(scripts / "ci-azure-e2e.sh")],
                env=env, text=True, capture_output=True, timeout=30,
            )
            events = [json.loads(line) for line in (root / "events.jsonl").read_text().splitlines()]
            logs = "\n".join(p.read_text() for p in (root / "artifacts/azure-sigs").glob("*.log"))
            return result, events, logs

    @staticmethod
    def builds(events):
        return [e for e in events if e["command"] == "make" and
                e["args"][0].startswith("build-azure-sig-")]

    def test_parallel_builds_have_independent_authenticated_sessions(self):
        for federated in (True, False):
            with self.subTest(federated=federated):
                result, events, logs = self.run_ci(federated=federated)
                self.assertEqual(0, result.returncode, result.stderr + logs)
                builds = self.builds(events)
                self.assertEqual({"build-azure-sig-" + t for t in TARGETS},
                                 {e["args"][0] for e in builds})
                self.assertEqual(2, len(builds))
                self.assertEqual(2, len({e["config"] for e in builds}))
                logins = [e for e in events if e["command"] == "az" and e["args"][0] == "login"]
                self.assertEqual(3, len(logins))
                self.assertEqual(3, len({e["config"] for e in logins}))
                for login in logins:
                    self.assertIn("--federated-token" if federated else "-p", login["args"])
                    self.assertIn("test-token" if federated else "test-secret", login["args"])
                for build in builds:
                    self.assertTrue(any(e["config"] == build["config"] for e in logins))
                    self.assertEqual("True" if federated else None, build["cli_auth"])
                lookup = next(e for e in events if e["args"][:3] == ["vm", "image", "show"])
                cleanup = next(e for e in events if e["args"][:2] == ["group", "delete"])
                self.assertEqual(lookup["config"], cleanup["config"])
                self.assertNotIn(lookup["config"], {e["config"] for e in builds})

    def test_custom_parent_config_and_cvm_location_are_preserved(self):
        result, events, logs = self.run_ci(custom_config=True, AZURE_LOCATION="australiaeast")
        self.assertEqual(0, result.returncode, result.stderr + logs)
        cleanup = next(e for e in events if e["args"][:2] == ["group", "delete"])
        self.assertTrue(cleanup["config"].endswith("/custom config"))
        self.assertEqual("australiaeast", cleanup["location"])
        for build in self.builds(events):
            self.assertNotEqual(cleanup["config"], build["config"])
            if build["args"][0].endswith("-cvm"):
                self.assertIn(build["location"], ("eastus", "germanywestcentral", "northeurope",
                                                "switzerlandnorth", "uksouth", "westeurope", "westus"))
            else:
                self.assertEqual("australiaeast", build["location"])

    def test_parent_login_failure_stops_before_builds(self):
        for federated in (True, False):
            with self.subTest(federated=federated):
                result, events, _ = self.run_ci(federated=federated, TEST_LOGIN_FAILURE="main")
                self.assertNotEqual(0, result.returncode)
                self.assertIn("simulated login failure", result.stderr)
                self.assertEqual([], self.builds(events))

    def test_child_login_failure_prevents_its_build(self):
        for federated in (True, False):
            with self.subTest(federated=federated):
                result, events, logs = self.run_ci(federated=federated, TEST_LOGIN_FAILURE=TARGETS[0])
                self.assertNotEqual(0, result.returncode)
                self.assertIn("simulated login failure", logs)
                self.assertEqual([["build-azure-sig-" + TARGETS[1]]],
                                 [e["args"] for e in self.builds(events)])

    def test_build_failure_is_reported(self):
        result, events, logs = self.run_ci(TEST_BUILD_FAILURE=TARGETS[0])
        self.assertNotEqual(0, result.returncode)
        self.assertIn("simulated build failure", logs)
        self.assertIn("sig-" + TARGETS[0] + ": FAILED", result.stdout)
        self.assertEqual(2, len(self.builds(events)))


if __name__ == "__main__":
    unittest.main()
