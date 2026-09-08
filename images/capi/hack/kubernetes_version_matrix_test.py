import importlib.util
from pathlib import Path


spec = importlib.util.spec_from_file_location("matrix", Path(__file__).with_name("kubernetes-version-matrix.py"))
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


def test_pin_policy_rejects_downgrade():
    tracked = matrix.TRACKED_REPOS[0]
    errors = matrix.pin_policy_errors("latest", {tracked.entry_key: "2.1.0"}, {tracked.entry_key: "2.0.0"})
    assert errors


def test_validate_entry_rejects_malformed_containerd():
    entry = {key: "1.0.0" for key in matrix.REQUIRED_KEYS}
    entry.update(kubernetes_semver="v1.31.0", kubernetes_series="v1.31", kubernetes_rpm_version="1.31.0", kubernetes_deb_version="1.31.0-1", kubernetes_cni_semver="v1.0.0", kubernetes_cni_rpm_version="1.0.0", kubernetes_cni_deb_version="1.0.0-1", containerd_version="2")
    assert any("containerd_version" in error for error in matrix.validate_entry("latest", entry))
