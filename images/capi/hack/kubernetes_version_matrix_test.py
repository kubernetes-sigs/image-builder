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
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "matrix", Path(__file__).with_name("kubernetes-version-matrix.py")
)
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)

ENTRY = {
    "containerd_version": "2.1.0",
    "crictl_version": "1.31.0",
    "kubernetes_cni_deb_version": "1.5.1-1.1",
    "kubernetes_cni_http_source": "https://example.org/cni.tgz",
    "kubernetes_cni_rpm_version": "1.5.1",
    "kubernetes_cni_semver": "v1.5.1",
    "kubernetes_deb_version": "1.31.0-1.1",
    "kubernetes_rpm_version": "1.31.0",
    "kubernetes_semver": "v1.31.0",
    "kubernetes_series": "v1.31",
    "runc_version": "1.2.0",
}


class MatrixTests(unittest.TestCase):
    def test_pin_policy_rejects_downgrade_but_allows_unchanged(self):
        for selector in ("latest", "1.31"):
            self.assertEqual(matrix.pin_policy_errors(selector, ENTRY, ENTRY), [])
            for tracked in matrix.TRACKED_REPOS:
                with self.subTest(selector=selector, dependency=tracked.entry_key):
                    values = dict(ENTRY)
                    major, minor, _ = values[tracked.entry_key].removeprefix("v").split(".")
                    values[tracked.entry_key] = (
                        ("" if tracked.unprefixed else "v")
                        + f"{major}.{int(minor) - 1}.0"
                    )
                    self.assertTrue(matrix.pin_policy_errors(selector, ENTRY, values))

    def test_verify_reports_malformed_versions_without_traceback(self):
        for key in ("containerd_version", "crictl_version", "runc_version"):
            for value in ("2", "v2.1.0", "2.1"):
                with self.subTest(key=key, value=value):
                    errors = io.StringIO()
                    with patch.object(matrix, "load_matrix", return_value=(
                        {}, {**ENTRY, key: value}
                    )), contextlib.redirect_stderr(errors):
                        self.assertEqual(matrix.verify(), 1)
                    self.assertIn(f"ERROR: latest: invalid {key}", errors.getvalue())

    def test_minor_change_refreshes_cni_packages_but_patch_keeps_them(self):
        for version, refresh in (("v1.32.0", True), ("v1.31.1", False)):
            with self.subTest(version=version):
                revs = {t.repo: matrix.tracking_rev(t, ENTRY) for t in matrix.TRACKED_REPOS}
                revs["https://github.com/kubernetes/kubernetes"] = version
                with contextlib.ExitStack() as stack:
                    stack.enter_context(patch.object(matrix, "read_tracking_config", return_value=revs))
                    stack.enter_context(patch.object(matrix, "resolve_kubernetes_deb_version", return_value="new-k8s"))
                    deb = stack.enter_context(patch.object(matrix, "resolve_cni_deb_version", return_value="new-deb"))
                    rpm = stack.enter_context(patch.object(matrix, "resolve_cni_rpm_version", return_value="new-rpm"))
                    result = matrix.entry_from_tracking("latest", ENTRY)
                if refresh:
                    deb.assert_called_once_with("1.32")
                    rpm.assert_called_once_with("1.32")
                else:
                    deb.assert_not_called()
                    rpm.assert_not_called()
                self.assertEqual(result["kubernetes_cni_deb_version"],
                                 "new-deb" if refresh else ENTRY["kubernetes_cni_deb_version"])
                self.assertEqual(result["kubernetes_cni_rpm_version"],
                                 "new-rpm" if refresh else ENTRY["kubernetes_cni_rpm_version"])
                self.assertEqual(result["kubernetes_cni_semver"], ENTRY["kubernetes_cni_semver"])

    def test_sync_reports_tracking_errors_without_writing(self):
        errors = io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(matrix, "load_matrix", return_value=({}, ENTRY)))
            stack.enter_context(patch.object(matrix, "entry_from_tracking", side_effect=ValueError("invalid rev")))
            write = stack.enter_context(patch.object(matrix, "apply_expected_files"))
            stack.enter_context(contextlib.redirect_stderr(errors))
            self.assertEqual(matrix.sync_tracking(True), 1)
        self.assertEqual(errors.getvalue(), "ERROR: invalid rev\n")
        write.assert_not_called()


if __name__ == "__main__":
    unittest.main()
