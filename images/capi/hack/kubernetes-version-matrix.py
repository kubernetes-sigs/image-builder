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

"""Render, verify, and refresh Kubernetes minor dependency matrix entries."""

from __future__ import annotations

import argparse
import difflib
import gzip
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


sys.dont_write_bytecode = True

CAPI_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = CAPI_ROOT.parents[1]
MATRIX_FILE = CAPI_ROOT / "packer/config/kubernetes-version-matrix.yaml"
LATEST_FILE = CAPI_ROOT / "packer/config/kubernetes-version-latest.yaml"
TRACKING_DIR = CAPI_ROOT / "packer/config/kubernetes-version-dependencies"
TRACKING_MODULE_PREFIX = (
    "sigs.k8s.io/image-builder/images/capi/packer/config/kubernetes-version-dependencies"
)
TRACKING_GO_VERSION = "1.24"
KUBERNETES_DEB_RESOLVER = (
    REPO_ROOT / ".github/actions/configure-k8s-version/resolve-kubernetes-deb-version.py"
)
KUBERNETES_STABLE_URL = "https://dl.k8s.io/release/stable-{minor}.txt"
KUBERNETES_LATEST_URL = "https://dl.k8s.io/release/stable.txt"
CRI_TOOLS_RELEASES_URL = (
    "https://api.github.com/repos/kubernetes-sigs/cri-tools/releases?per_page=100"
)
CNI_DEB_PACKAGES_URL = "https://pkgs.k8s.io/core:/stable:/v{minor}/deb/Packages"
CNI_RPM_REPOMD_URL = (
    "https://pkgs.k8s.io/core:/stable:/v{minor}/rpm/repodata/repomd.xml"
)
CNI_RPM_BASE_URL = "https://pkgs.k8s.io/core:/stable:/v{minor}/rpm/{path}"
REQUIRED_KEYS = (
    "containerd_version",
    "crictl_version",
    "kubernetes_cni_deb_version",
    "kubernetes_cni_http_source",
    "kubernetes_cni_rpm_version",
    "kubernetes_cni_semver",
    "kubernetes_deb_version",
    "kubernetes_rpm_version",
    "kubernetes_semver",
    "kubernetes_series",
    "runc_version",
)
TRACKED_GO_MODULES = (
    ("github.com/containerd/containerd/v2", "containerd_version"),
    ("github.com/containernetworking/plugins", "kubernetes_cni_semver"),
    ("github.com/opencontainers/runc", "runc_version"),
    ("k8s.io/client-go", "kubernetes_semver"),
    ("sigs.k8s.io/cri-tools", "crictl_version"),
)


def ensure_yq() -> str:
    yq = shutil.which("yq")
    if yq:
        return yq

    subprocess.run([str(CAPI_ROOT / "hack/ensure-yq.sh")], check=True)
    yq = shutil.which("yq") or str(CAPI_ROOT / ".local/bin/yq")
    if not Path(yq).exists():
        raise RuntimeError("yq is required to read the matrix YAML files")
    return yq


def yq_json(path: Path, expression: str) -> Any:
    result = subprocess.run(
        [ensure_yq(), "-o=json", expression, str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def load_matrix() -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    release_pins = yq_json(MATRIX_FILE, ".releasePins")
    latest = yq_json(LATEST_FILE, ".latest")
    return release_pins, latest


def render_entry(selector: str) -> dict[str, Any]:
    release_pins, latest = load_matrix()
    if selector == "latest":
        return latest
    if selector not in release_pins:
        valid = ", ".join(["latest", *sorted(release_pins)])
        raise ValueError(f"unknown selector {selector!r}; expected one of: {valid}")
    return release_pins[selector]


def version_sort_key(version: str) -> tuple[object, ...]:
    return tuple(
        int(part) if part.isdigit() else part
        for part in re.findall(r"\d+|\D+", version)
    )


def fetch_text(url: str, headers: dict[str, str] | None = None) -> str:
    request = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def fetch_bytes(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def stable_kubernetes_version(minor: str | None = None) -> str:
    url = KUBERNETES_LATEST_URL if minor is None else KUBERNETES_STABLE_URL.format(minor=minor)
    version = fetch_text(url).strip()
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        raise ValueError(f"unexpected Kubernetes version from {url}: {version}")
    return version


def load_deb_resolver():
    spec = importlib.util.spec_from_file_location(
        "resolve_kubernetes_deb_version", KUBERNETES_DEB_RESOLVER
    )
    if not spec or not spec.loader:
        raise RuntimeError(f"failed to load {KUBERNETES_DEB_RESOLVER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def resolve_kubernetes_deb_version(version: str) -> str:
    resolver = load_deb_resolver()
    series = ".".join(version.removeprefix("v").split(".")[:2])
    packages_url = resolver.PACKAGES_URL.format(series=series)
    packages = resolver.parse_packages(resolver.load_packages(packages_url))
    return resolver.resolve_deb_version(version.removeprefix("v"), packages, "amd64")


def resolve_cni_deb_version(minor: str, cni_version: str | None = None) -> str:
    packages = fetch_text(CNI_DEB_PACKAGES_URL.format(minor=minor))
    versions = []
    for stanza in packages.split("\n\n"):
        fields = dict(line.split(": ", 1) for line in stanza.splitlines() if ": " in line)
        if fields.get("Package") == "kubernetes-cni" and fields.get("Architecture") == "amd64":
            versions.append(fields["Version"])
    if not versions:
        raise ValueError(f"no kubernetes-cni Debian package found for Kubernetes {minor}")
    if cni_version is not None:
        matching_versions = [
            version for version in versions if version.startswith(f"{cni_version}-")
        ]
        if not matching_versions:
            raise ValueError(
                f"no kubernetes-cni Debian package {cni_version!r} found "
                f"for Kubernetes {minor}"
            )
        versions = matching_versions
    return sorted(versions, key=version_sort_key)[-1]


def resolve_cni_rpm_version(minor: str, cni_version: str | None = None) -> str:
    repomd = fetch_bytes(CNI_RPM_REPOMD_URL.format(minor=minor))
    root = ET.fromstring(repomd)
    repo_ns = {"repo": "http://linux.duke.edu/metadata/repo"}
    primary = root.find("repo:data[@type='primary']/repo:location", repo_ns)
    if primary is None:
        raise ValueError(f"no RPM primary metadata found for Kubernetes {minor}")

    primary_xml = gzip.decompress(
        fetch_bytes(CNI_RPM_BASE_URL.format(minor=minor, path=primary.attrib["href"]))
    )
    primary_root = ET.fromstring(primary_xml)
    common_ns = {"common": "http://linux.duke.edu/metadata/common"}
    versions = []
    for package in primary_root.findall("common:package", common_ns):
        name = package.findtext("common:name", namespaces=common_ns)
        arch = package.findtext("common:arch", namespaces=common_ns)
        if name == "kubernetes-cni" and arch == "x86_64":
            version = package.find("common:version", common_ns)
            if version is not None:
                versions.append(version.attrib["ver"])
    if not versions:
        raise ValueError(f"no kubernetes-cni RPM package found for Kubernetes {minor}")
    if cni_version is not None:
        matching_versions = [version for version in versions if version == cni_version]
        if not matching_versions:
            raise ValueError(
                f"no kubernetes-cni RPM package {cni_version!r} found "
                f"for Kubernetes {minor}"
            )
        versions = matching_versions
    return sorted(versions, key=version_sort_key)[-1]


def resolve_crictl_version(minor: str) -> str:
    headers = {}
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    releases = json.loads(fetch_text(CRI_TOOLS_RELEASES_URL, headers=headers))
    versions = []
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = release.get("tag_name", "")
        if re.fullmatch(rf"v{re.escape(minor)}\.\d+", tag):
            versions.append(tag.removeprefix("v"))
    if not versions:
        raise ValueError(f"no cri-tools release found for Kubernetes {minor}")
    return sorted(versions, key=version_sort_key)[-1]


def refresh_entry(selector: str, current: dict[str, Any]) -> dict[str, Any]:
    kubernetes_semver = stable_kubernetes_version(selector)
    kubernetes_version = kubernetes_semver.removeprefix("v")
    cni_rpm_version = resolve_cni_rpm_version(selector)
    updated = dict(current)
    updated.update(
        {
            "crictl_version": resolve_crictl_version(selector),
            "kubernetes_cni_deb_version": resolve_cni_deb_version(selector),
            "kubernetes_cni_rpm_version": cni_rpm_version,
            "kubernetes_cni_semver": f"v{cni_rpm_version}",
            "kubernetes_deb_version": resolve_kubernetes_deb_version(kubernetes_version),
            "kubernetes_rpm_version": kubernetes_version,
            "kubernetes_semver": kubernetes_semver,
            "kubernetes_series": f"v{selector}",
        }
    )
    return {key: updated[key] for key in REQUIRED_KEYS}


def refresh_matrix() -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    release_pins, latest = load_matrix()
    refreshed_pins = {
        selector: refresh_entry(selector, release_pins[selector])
        for selector in sorted(release_pins, key=version_sort_key)
    }

    latest_semver = stable_kubernetes_version()
    latest_selector = ".".join(latest_semver.removeprefix("v").split(".")[:2])
    latest_base = refreshed_pins.get(latest_selector, latest)
    refreshed_latest = refresh_entry(latest_selector, latest_base)
    return refreshed_pins, refreshed_latest


def yaml_scalar(value: Any) -> str:
    if value is None:
        return "null"
    return json.dumps(str(value))


def render_release_matrix_yaml(release_pins: dict[str, dict[str, Any]]) -> str:
    lines = [
        "# Copyright 2026 The Kubernetes Authors.",
        "#",
        "# Licensed under the Apache License, Version 2.0 (the \"License\");",
        "# you may not use this file except in compliance with the License.",
        "# You may obtain a copy of the License at",
        "#",
        "#     http://www.apache.org/licenses/LICENSE-2.0",
        "#",
        "# Unless required by applicable law or agreed to in writing, software",
        "# distributed under the License is distributed on an \"AS IS\" BASIS,",
        "# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.",
        "# See the License for the specific language governing permissions and",
        "# limitations under the License.",
        "#",
        "# Canonical release-pinned Kubernetes minor dependency matrix.",
        "# Render an entry to a Packer var file with:",
        "#   images/capi/hack/kubernetes-version-matrix.py render 1.36",
        "releasePins:",
    ]
    for selector in sorted(release_pins, key=version_sort_key):
        lines.append(f"  {yaml_scalar(selector)}:")
        for key in REQUIRED_KEYS:
            lines.append(f"    {key}: {yaml_scalar(release_pins[selector][key])}")
    return "\n".join(lines) + "\n"


def render_latest_yaml(latest: dict[str, Any]) -> str:
    lines = [
        "# Copyright 2026 The Kubernetes Authors.",
        "#",
        "# Licensed under the Apache License, Version 2.0 (the \"License\");",
        "# you may not use this file except in compliance with the License.",
        "# You may obtain a copy of the License at",
        "#",
        "#     http://www.apache.org/licenses/LICENSE-2.0",
        "#",
        "# Unless required by applicable law or agreed to in writing, software",
        "# distributed under the License is distributed on an \"AS IS\" BASIS,",
        "# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.",
        "# See the License for the specific language governing permissions and",
        "# limitations under the License.",
        "#",
        "# Rolling latest Kubernetes dependency entry.",
        "# Refresh with:",
        "#   images/capi/hack/kubernetes-version-matrix.py update --write",
        "latest:",
    ]
    for key in REQUIRED_KEYS:
        lines.append(f"  {key}: {yaml_scalar(latest[key])}")
    return "\n".join(lines) + "\n"


def tracking_selector_name(selector: str) -> str:
    if selector == "latest":
        return "latest"
    return f"release-{selector.replace('.', '-')}"


def tracking_go_mod_path(selector: str) -> Path:
    return TRACKING_DIR / tracking_selector_name(selector) / "go.mod"


def kubernetes_module_version(kubernetes_semver: Any) -> str:
    version = str(kubernetes_semver).removeprefix("v")
    major, minor, patch = version.split(".", 2)
    if major != "1":
        raise ValueError(f"expected Kubernetes major version 1, got {kubernetes_semver}")
    return f"v0.{minor}.{patch}"


def kubernetes_semver_from_module(module_version: str) -> str:
    version = module_version.removeprefix("v")
    major, minor, patch = version.split(".", 2)
    if major != "0":
        raise ValueError(f"expected Kubernetes module major version 0, got {module_version}")
    return f"v1.{minor}.{patch}"


def go_module_version(module: str, value: Any) -> str:
    if module == "k8s.io/client-go":
        return kubernetes_module_version(value)
    version = str(value)
    if version.startswith("v"):
        return version
    return f"v{version}"


def render_tracking_go_mod(selector: str, entry: dict[str, Any]) -> str:
    module_name = f"{TRACKING_MODULE_PREFIX}/{tracking_selector_name(selector)}"
    lines = [
        f"module {module_name}",
        "",
        f"go {TRACKING_GO_VERSION}",
        "",
        "require (",
    ]
    for module, entry_key in TRACKED_GO_MODULES:
        lines.append(f"\t{module} {go_module_version(module, entry[entry_key])}")
    lines.append(")")
    return "\n".join(lines) + "\n"


def render_tracking_go_mods(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any]
) -> dict[Path, str]:
    manifests = {
        tracking_go_mod_path(selector): render_tracking_go_mod(selector, release_pins[selector])
        for selector in sorted(release_pins, key=version_sort_key)
    }
    manifests[tracking_go_mod_path("latest")] = render_tracking_go_mod("latest", latest)
    return manifests


def read_tracking_go_mod(selector: str) -> dict[str, str]:
    path = tracking_go_mod_path(selector)
    if not path.exists():
        raise FileNotFoundError(f"{path} does not exist")

    versions: dict[str, str] = {}
    in_require_block = False
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if stripped == "require (":
            in_require_block = True
            continue
        if in_require_block and stripped == ")":
            in_require_block = False
            continue
        if stripped.startswith("require "):
            stripped = stripped.removeprefix("require ").strip()
        if not in_require_block and " " not in stripped:
            continue
        parts = stripped.split()
        if len(parts) >= 2:
            versions[parts[0]] = parts[1]
    return versions


def entry_from_tracking(selector: str, current: dict[str, Any]) -> dict[str, Any]:
    versions = read_tracking_go_mod(selector)
    missing_modules = [
        module for module, _ in TRACKED_GO_MODULES if module not in versions
    ]
    if missing_modules:
        raise ValueError(
            f"{selector}: tracking manifest missing modules: {', '.join(missing_modules)}"
        )

    kubernetes_semver = kubernetes_semver_from_module(versions["k8s.io/client-go"])
    kubernetes_version = kubernetes_semver.removeprefix("v")
    kubernetes_minor = ".".join(kubernetes_version.split(".")[:2])
    if selector != "latest" and kubernetes_minor != selector:
        raise ValueError(
            f"{selector}: tracking manifest points to Kubernetes {kubernetes_minor}, "
            f"expected {selector}"
        )

    cni_semver = versions["github.com/containernetworking/plugins"]
    cni_version = cni_semver.removeprefix("v")
    cni_rpm_version = resolve_cni_rpm_version(kubernetes_minor, cni_version)
    updated = dict(current)
    updated.update(
        {
            "containerd_version": versions[
                "github.com/containerd/containerd/v2"
            ].removeprefix("v"),
            "crictl_version": versions["sigs.k8s.io/cri-tools"].removeprefix("v"),
            "kubernetes_cni_deb_version": resolve_cni_deb_version(
                kubernetes_minor, cni_version
            ),
            "kubernetes_cni_rpm_version": cni_rpm_version,
            "kubernetes_cni_semver": f"v{cni_rpm_version}",
            "kubernetes_deb_version": resolve_kubernetes_deb_version(kubernetes_version),
            "kubernetes_rpm_version": kubernetes_version,
            "kubernetes_semver": kubernetes_semver,
            "kubernetes_series": f"v{kubernetes_minor}",
            "runc_version": versions["github.com/opencontainers/runc"].removeprefix("v"),
        }
    )
    return {key: updated[key] for key in REQUIRED_KEYS}


def expected_files(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any]
) -> dict[Path, str]:
    return {
        MATRIX_FILE: render_release_matrix_yaml(release_pins),
        LATEST_FILE: render_latest_yaml(latest),
        **render_tracking_go_mods(release_pins, latest),
    }


def apply_expected_files(expected: dict[Path, str], write: bool) -> bool:
    changed = False
    for path, content in expected.items():
        current = path.read_text() if path.exists() else ""
        if current == content:
            continue
        changed = True
        if write:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            continue
        diff = difflib.unified_diff(
            current.splitlines(True),
            content.splitlines(True),
            fromfile=str(path),
            tofile=f"{path} (updated)",
        )
        sys.stdout.writelines(diff)
    return changed


def validate_entry(selector: str, entry: dict[str, Any]) -> list[str]:
    errors = []
    missing = [key for key in REQUIRED_KEYS if key not in entry]
    if missing:
        errors.append(f"{selector}: missing keys: {', '.join(missing)}")
        return errors

    kubernetes_semver = entry["kubernetes_semver"]
    kubernetes_version = kubernetes_semver.removeprefix("v")
    kubernetes_minor = ".".join(kubernetes_version.split(".")[:2])
    if not re.fullmatch(r"v\d+\.\d+\.\d+", kubernetes_semver):
        errors.append(f"{selector}: invalid kubernetes_semver {kubernetes_semver!r}")
    if entry["kubernetes_series"] != f"v{kubernetes_minor}":
        errors.append(f"{selector}: kubernetes_series does not match kubernetes_semver")
    if entry["kubernetes_rpm_version"] != kubernetes_version:
        errors.append(f"{selector}: kubernetes_rpm_version does not match kubernetes_semver")
    if not str(entry["kubernetes_deb_version"]).startswith(f"{kubernetes_version}-"):
        errors.append(f"{selector}: kubernetes_deb_version does not match kubernetes_semver")
    cni_rpm = entry["kubernetes_cni_rpm_version"]
    if entry["kubernetes_cni_semver"] != f"v{cni_rpm}":
        errors.append(f"{selector}: kubernetes_cni_semver does not match RPM CNI version")
    if not str(entry["kubernetes_cni_deb_version"]).startswith(f"{cni_rpm}-"):
        errors.append(f"{selector}: DEB and RPM CNI versions do not match")
    return errors


def verify() -> int:
    release_pins, latest = load_matrix()
    errors: list[str] = []
    for selector, entry in release_pins.items():
        errors.extend(validate_entry(selector, entry))
    errors.extend(validate_entry("latest", latest))

    expected_tracking = render_tracking_go_mods(release_pins, latest)
    for path, expected in expected_tracking.items():
        if not path.exists():
            errors.append(f"{path}: missing generated Dependabot tracking manifest")
            continue
        current = path.read_text()
        if current != expected:
            errors.append(f"{path}: generated Dependabot tracking manifest is out of date")

    expected_paths = set(expected_tracking)
    for path in TRACKING_DIR.glob("*/go.mod"):
        if path not in expected_paths:
            errors.append(f"{path}: unexpected Dependabot tracking manifest")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("Kubernetes version matrix is valid")
    return 0


def update(write: bool) -> int:
    release_pins, latest = refresh_matrix()
    changed = apply_expected_files(expected_files(release_pins, latest), write)

    if changed and not write:
        print("Kubernetes version matrix is out of date; rerun with --write", file=sys.stderr)
        return 1
    return verify()


def sync_tracking(write: bool) -> int:
    release_pins, latest = load_matrix()
    synced_pins = {
        selector: entry_from_tracking(selector, release_pins[selector])
        for selector in sorted(release_pins, key=version_sort_key)
    }
    synced_latest = entry_from_tracking("latest", latest)
    changed = apply_expected_files(expected_files(synced_pins, synced_latest), write)

    if changed and not write:
        print(
            "Kubernetes version matrix does not match tracking manifests; "
            "rerun with --write",
            file=sys.stderr,
        )
        return 1
    return verify()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    render_parser = subparsers.add_parser("render", help="render one matrix entry as JSON")
    render_parser.add_argument("selector", nargs="?", default="latest")

    subparsers.add_parser("verify", help="verify matrix structure and tracking manifests")

    update_parser = subparsers.add_parser("update", help="refresh Kubernetes package pins")
    update_parser.add_argument("--write", action="store_true", help="write refreshed YAML files")

    sync_parser = subparsers.add_parser(
        "sync-tracking", help="refresh matrix YAML from Dependabot tracking manifests"
    )
    sync_parser.add_argument("--write", action="store_true", help="write refreshed YAML files")

    args = parser.parse_args()
    if args.command == "render":
        print(json.dumps(render_entry(args.selector), indent=2, sort_keys=True))
        return 0
    if args.command == "verify":
        return verify()
    if args.command == "update":
        return update(args.write)
    if args.command == "sync-tracking":
        return sync_tracking(args.write)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
