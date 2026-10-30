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
import fnmatch
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
from typing import Any, NamedTuple


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
DEPENDABOT_FILE = REPO_ROOT / ".github/dependabot.yml"
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
LICENSE_HEADER = """// Copyright 2026 The Kubernetes Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
"""


class TrackedModule(NamedTuple):
    """One synthetic Go module that tracks a single matrix dependency.

    ``package`` is the lightest importable package in ``module``. It only has
    to pull the module into the requirement graph, so the fewer transitive
    imports it has, the fewer indirect requirements ``go mod tidy`` records.
    """

    name: str
    module: str
    entry_key: str
    package: str


TRACKED_GO_MODULES = (
    TrackedModule(
        "containerd",
        "github.com/containerd/containerd/v2",
        "containerd_version",
        "github.com/containerd/containerd/v2/version",
    ),
    TrackedModule(
        "cni-plugins",
        "github.com/containernetworking/plugins",
        "kubernetes_cni_semver",
        "github.com/containernetworking/plugins/pkg/utils/buildversion",
    ),
    TrackedModule(
        "runc",
        "github.com/opencontainers/runc",
        "runc_version",
        "github.com/opencontainers/runc/types/features",
    ),
    TrackedModule(
        "kubernetes",
        "k8s.io/client-go",
        "kubernetes_semver",
        "k8s.io/client-go/util/homedir",
    ),
    TrackedModule(
        "cri-tools",
        "sigs.k8s.io/cri-tools",
        "crictl_version",
        "sigs.k8s.io/cri-tools/pkg/version",
    ),
)
TOOLS_IMPORT_RE = re.compile(r'^\s*_\s+"([^"]+)"', re.MULTILINE)
GO_MOD_BLOCK_RE = re.compile(r"(require|exclude|replace|retract)\s*\(")


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
    """Refresh the pins one selector resolves from upstream release metadata.

    Only the Kubernetes version fields, the kubernetes-cni package versions and
    crictl are refreshed here. ``containerd_version``, ``runc_version`` and
    ``kubernetes_cni_semver`` are deliberately carried over from ``current``:
    Dependabot tracks each of them in its own tracking module, and the CNI
    plugins tarball in particular does not have to match the kubernetes-cni
    package version.
    """
    kubernetes_semver = stable_kubernetes_version(selector)
    kubernetes_version = kubernetes_semver.removeprefix("v")
    cni_rpm_version = resolve_cni_rpm_version(selector)
    updated = dict(current)
    updated.update(
        {
            "crictl_version": resolve_crictl_version(selector),
            "kubernetes_cni_deb_version": resolve_cni_deb_version(selector),
            "kubernetes_cni_rpm_version": cni_rpm_version,
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
    # Refresh the rolling entry from its own values, never from the release pin
    # for the same minor. containerd, runc and the CNI plugins tarball are
    # tracked separately for latest and may legitimately run ahead of the pin,
    # so seeding from the pin would silently roll them back.
    refreshed_latest = refresh_entry(latest_selector, latest)
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


def tracking_module_dir(selector: str, tracked: TrackedModule) -> Path:
    return TRACKING_DIR / tracking_selector_name(selector) / tracked.name


def tracking_module_path(selector: str, tracked: TrackedModule) -> str:
    return f"{TRACKING_MODULE_PREFIX}/{tracking_selector_name(selector)}/{tracked.name}"


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


def render_tracking_go_mod(module_path: str, tracked: TrackedModule, version: str) -> str:
    return (
        f"module {module_path}\n"
        "\n"
        f"go {TRACKING_GO_VERSION}\n"
        "\n"
        f"require {tracked.module} {version}\n"
    )


def render_tracking_tools_go(tracked: TrackedModule) -> str:
    return LICENSE_HEADER + (
        "\n"
        "//go:build tools\n"
        "\n"
        "// Package tools keeps the tracked module in go.mod. Dependabot always\n"
        "// runs go mod tidy after an update, and tidy drops requirements that no\n"
        "// package imports.\n"
        "package tools\n"
        "\n"
        "import (\n"
        f'\t_ "{tracked.package}"\n'
        ")\n"
    )


def tracking_entries(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any]
) -> list[tuple[str, dict[str, Any]]]:
    entries = [
        (selector, release_pins[selector])
        for selector in sorted(release_pins, key=version_sort_key)
    ]
    entries.append(("latest", latest))
    return entries


def expected_tracking_modules(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any]
) -> dict[Path, tuple[str, TrackedModule, str]]:
    """Map every expected module directory to its module path, dependency and version."""
    modules: dict[Path, tuple[str, TrackedModule, str]] = {}
    for selector, entry in tracking_entries(release_pins, latest):
        for tracked in TRACKED_GO_MODULES:
            modules[tracking_module_dir(selector, tracked)] = (
                tracking_module_path(selector, tracked),
                tracked,
                go_module_version(tracked.module, entry[tracked.entry_key]),
            )
    return modules


def parse_go_mod(path: Path) -> tuple[str, dict[str, str]]:
    """Return the module path and the direct requirements of a go.mod file."""
    module_path = ""
    requires: dict[str, str] = {}
    in_require_block = False
    for raw_line in path.read_text().splitlines():
        code, _, comment = raw_line.partition("//")
        line = code.strip()
        if not line:
            continue
        if line.startswith("module "):
            module_path = line.removeprefix("module ").strip()
            continue
        if in_require_block:
            if line == ")":
                in_require_block = False
                continue
        elif line == "require (":
            in_require_block = True
            continue
        elif line.startswith("require "):
            line = line.removeprefix("require ").strip()
            if line == "(":
                in_require_block = True
                continue
        else:
            continue
        if "indirect" in comment:
            continue
        parts = line.split()
        if len(parts) >= 2:
            requires[parts[0]] = parts[1]
    return module_path, requires


def go_sum_modules(path: Path) -> set[tuple[str, str]]:
    """Return the (module, version) pairs a go.sum records an h1: checksum for.

    ``version`` keeps the ``/go.mod`` suffix of the manifest-only lines, so a
    caller can tell the two kinds of checksum apart.
    """
    recorded = set()
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2].startswith("h1:"):
            recorded.add((parts[0], parts[1]))
    return recorded


def tracking_tools_packages(path: Path) -> list[str]:
    return TOOLS_IMPORT_RE.findall(path.read_text())


def set_go_mod_require(path: Path, module: str, version: str) -> bool:
    """Rewrite the direct requirement on ``module`` in place.

    Every other line is left alone, including requirements marked
    ``// indirect`` and any mention of the module inside an exclude, replace or
    retract block.
    """
    pattern = re.compile(rf"^(\s*(?:require\s+)?){re.escape(module)}\s+\S+(.*)$")
    lines = path.read_text().splitlines(keepends=True)
    block = ""
    changed = False
    for index, raw_line in enumerate(lines):
        line = raw_line.rstrip("\n")
        code, _, comment = line.partition("//")
        stripped = code.strip()

        if block:
            if stripped == ")":
                block = ""
            in_require = block == "require"
        elif opened := GO_MOD_BLOCK_RE.fullmatch(stripped):
            block = opened.group(1)
            continue
        else:
            in_require = stripped.startswith("require ")

        if not in_require or "indirect" in comment:
            continue
        match = pattern.match(line)
        if not match:
            continue
        replacement = f"{match.group(1)}{module} {version}{match.group(2)}"
        if replacement != line:
            lines[index] = replacement + "\n"
            changed = True
    if changed:
        path.write_text("".join(lines))
    return changed


def missing_go_error() -> str | None:
    """Return an error message when the go command is unavailable, else None."""
    if shutil.which("go"):
        return None
    return (
        "the go command is required to write tracking modules because each one is "
        "regenerated with 'go mod tidy'; install Go and rerun"
    )


def go_mod_tidy(directory: Path) -> None:
    go = shutil.which("go")
    if not go:
        raise RuntimeError(f"{missing_go_error()} (needed for {directory})")
    subprocess.run([go, "mod", "tidy"], check=True, cwd=directory)


def tracking_module_issues(
    directory: Path, module_path: str, tracked: TrackedModule, version: str
) -> list[str]:
    """Report why a tracking module does not match the matrix; empty when it does."""
    go_mod = directory / "go.mod"
    if not go_mod.exists():
        return [f"{go_mod}: missing Dependabot tracking module"]

    issues = []
    current_module, requires = parse_go_mod(go_mod)
    if current_module != module_path:
        issues.append(f"{go_mod}: module is {current_module!r}, expected {module_path!r}")
    if tracked.module not in requires:
        issues.append(f"{go_mod}: {tracked.module} is not a direct requirement")
    elif requires[tracked.module] != version:
        issues.append(
            f"{go_mod}: {tracked.module} is {requires[tracked.module]}, expected {version}"
        )
    go_sum = directory / "go.sum"
    if not go_sum.exists():
        issues.append(f"{go_sum}: missing checksum file")
    else:
        recorded = go_sum_modules(go_sum)
        issues.extend(
            f"{go_sum}: no h1: checksum for {tracked.module} {version}{suffix}"
            for suffix in ("", "/go.mod")
            if (tracked.module, f"{version}{suffix}") not in recorded
        )

    tools_go = directory / "tools.go"
    if not tools_go.exists():
        issues.append(f"{tools_go}: missing tools file")
    elif not any(
        package == tracked.module or package.startswith(f"{tracked.module}/")
        for package in tracking_tools_packages(tools_go)
    ):
        issues.append(f"{tools_go}: no blank import of a {tracked.module} package")
    return issues


def unexpected_tracking_files(expected_dirs: set[Path]) -> list[str]:
    if not TRACKING_DIR.exists():
        return []
    return [
        f"{path}: unexpected Dependabot tracking file"
        for path in sorted(TRACKING_DIR.rglob("*"))
        if path.is_file() and path.parent not in expected_dirs
    ]


def dependabot_gomod_directories() -> list[str]:
    config = yq_json(DEPENDABOT_FILE, ".")
    patterns = []
    for update in config.get("updates") or []:
        if update.get("package-ecosystem") != "gomod":
            continue
        if directory := update.get("directory"):
            patterns.append(directory)
        patterns.extend(update.get("directories") or [])
    return patterns


def dependabot_coverage_issues(expected_dirs: set[Path]) -> list[str]:
    """Check that the gomod entries cover every tracking module and nothing else."""
    tracking_prefix = f"/{TRACKING_DIR.relative_to(REPO_ROOT).as_posix()}/"
    wanted = sorted(f"/{path.relative_to(REPO_ROOT).as_posix()}" for path in expected_dirs)
    patterns = dependabot_gomod_directories()

    issues = []
    for directory in wanted:
        if not any(fnmatch.fnmatch(directory, pattern) for pattern in patterns):
            issues.append(f"{DEPENDABOT_FILE}: no gomod entry covers {directory}")
    for pattern in patterns:
        if not pattern.startswith(tracking_prefix):
            issues.append(
                f"{DEPENDABOT_FILE}: gomod entry {pattern!r} points outside {tracking_prefix}"
            )
        elif not any(fnmatch.fnmatch(directory, pattern) for directory in wanted):
            issues.append(
                f"{DEPENDABOT_FILE}: gomod entry {pattern!r} matches no tracking module"
            )
    return issues


def write_tracking_module(
    directory: Path, module_path: str, tracked: TrackedModule, version: str
) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    go_mod = directory / "go.mod"
    current_module, requires = parse_go_mod(go_mod) if go_mod.exists() else ("", {})
    if current_module == module_path and tracked.module in requires:
        set_go_mod_require(go_mod, tracked.module, version)
    else:
        go_mod.write_text(render_tracking_go_mod(module_path, tracked, version))
    (directory / "tools.go").write_text(render_tracking_tools_go(tracked))
    go_mod_tidy(directory)


def sync_tracking_modules(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any], write: bool
) -> bool:
    """Bring the tracking modules in line with the matrix. True when they changed."""
    expected = expected_tracking_modules(release_pins, latest)
    changed = False
    for directory, (module_path, tracked, version) in sorted(expected.items()):
        issues = tracking_module_issues(directory, module_path, tracked, version)
        if not issues:
            continue
        changed = True
        if write:
            write_tracking_module(directory, module_path, tracked, version)
            continue
        for issue in issues:
            print(issue, file=sys.stderr)

    for stale in unexpected_tracking_files(set(expected)):
        changed = True
        print(stale, file=sys.stderr)
    return changed


def read_tracking_versions(selector: str) -> dict[str, str]:
    versions: dict[str, str] = {}
    missing = []
    for tracked in TRACKED_GO_MODULES:
        go_mod = tracking_module_dir(selector, tracked) / "go.mod"
        if not go_mod.exists():
            missing.append(str(go_mod))
            continue
        _, requires = parse_go_mod(go_mod)
        if tracked.module not in requires:
            missing.append(f"{go_mod} ({tracked.module})")
            continue
        versions[tracked.module] = requires[tracked.module]
    if missing:
        raise ValueError(
            f"{selector}: tracking modules missing requirements: {', '.join(missing)}"
        )
    return versions


def entry_from_tracking(selector: str, current: dict[str, Any]) -> dict[str, Any]:
    """Fold the versions Dependabot maintains back into one matrix entry.

    The kubernetes-cni package versions are not touched. They pin the distro
    package, which is versioned separately from the CNI plugins tarball that
    ``kubernetes_cni_semver`` selects.
    """
    versions = read_tracking_versions(selector)
    kubernetes_semver = kubernetes_semver_from_module(versions["k8s.io/client-go"])
    kubernetes_version = kubernetes_semver.removeprefix("v")
    kubernetes_minor = ".".join(kubernetes_version.split(".")[:2])
    if selector != "latest" and kubernetes_minor != selector:
        raise ValueError(
            f"{selector}: tracking module points to Kubernetes {kubernetes_minor}, "
            f"expected {selector}"
        )

    deb_version = current.get("kubernetes_deb_version")
    if current.get("kubernetes_rpm_version") != kubernetes_version or not deb_version:
        deb_version = resolve_kubernetes_deb_version(kubernetes_version)

    updated = dict(current)
    updated.update(
        {
            "containerd_version": versions[
                "github.com/containerd/containerd/v2"
            ].removeprefix("v"),
            "crictl_version": versions["sigs.k8s.io/cri-tools"].removeprefix("v"),
            "kubernetes_cni_semver": versions["github.com/containernetworking/plugins"],
            "kubernetes_deb_version": deb_version,
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
    if selector != "latest" and kubernetes_minor != selector:
        errors.append(
            f"{selector}: kubernetes_semver {kubernetes_semver!r} does not match "
            f"the {selector!r} release pin"
        )
    if entry["kubernetes_series"] != f"v{kubernetes_minor}":
        errors.append(f"{selector}: kubernetes_series does not match kubernetes_semver")
    if entry["kubernetes_rpm_version"] != kubernetes_version:
        errors.append(f"{selector}: kubernetes_rpm_version does not match kubernetes_semver")
    if not str(entry["kubernetes_deb_version"]).startswith(f"{kubernetes_version}-"):
        errors.append(f"{selector}: kubernetes_deb_version does not match kubernetes_semver")
    # kubernetes_cni_semver pins the CNI plugins tarball and is tracked on its
    # own, so it is only checked for shape, not against the package versions.
    if not re.fullmatch(r"v\d+\.\d+\.\d+", str(entry["kubernetes_cni_semver"])):
        errors.append(
            f"{selector}: invalid kubernetes_cni_semver {entry['kubernetes_cni_semver']!r}"
        )
    cni_rpm = entry["kubernetes_cni_rpm_version"]
    if not str(entry["kubernetes_cni_deb_version"]).startswith(f"{cni_rpm}-"):
        errors.append(f"{selector}: DEB and RPM CNI versions do not match")
    return errors


def verify() -> int:
    release_pins, latest = load_matrix()
    errors: list[str] = []
    for selector, entry in release_pins.items():
        errors.extend(validate_entry(selector, entry))
    errors.extend(validate_entry("latest", latest))

    expected = expected_tracking_modules(release_pins, latest)
    for directory, (module_path, tracked, version) in sorted(expected.items()):
        errors.extend(tracking_module_issues(directory, module_path, tracked, version))
    errors.extend(unexpected_tracking_files(set(expected)))
    errors.extend(dependabot_coverage_issues(set(expected)))

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("Kubernetes version matrix is valid")
    return 0


def update(write: bool) -> int:
    if write and (error := missing_go_error()):
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    release_pins, latest = refresh_matrix()
    changed = apply_expected_files(expected_files(release_pins, latest), write)
    changed = sync_tracking_modules(release_pins, latest, write) or changed

    if changed and not write:
        print("Kubernetes version matrix is out of date; rerun with --write", file=sys.stderr)
        return 1
    return verify()


def render_tracking(write: bool) -> int:
    if write and (error := missing_go_error()):
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    release_pins, latest = load_matrix()
    if sync_tracking_modules(release_pins, latest, write) and not write:
        print(
            "Dependabot tracking modules do not match the matrix; rerun with --write",
            file=sys.stderr,
        )
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
            "Kubernetes version matrix does not match tracking modules; rerun with --write",
            file=sys.stderr,
        )
        return 1
    return verify()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    render_parser = subparsers.add_parser("render", help="render one matrix entry as JSON")
    render_parser.add_argument("selector", nargs="?", default="latest")

    subparsers.add_parser("verify", help="verify matrix structure and tracking modules")

    update_parser = subparsers.add_parser("update", help="refresh Kubernetes package pins")
    update_parser.add_argument("--write", action="store_true", help="write refreshed files")

    render_tracking_parser = subparsers.add_parser(
        "render-tracking", help="create or repair Dependabot tracking modules from the matrix"
    )
    render_tracking_parser.add_argument(
        "--write", action="store_true", help="write the tracking modules"
    )

    sync_parser = subparsers.add_parser(
        "sync-tracking", help="refresh matrix YAML from Dependabot tracking modules"
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
    if args.command == "render-tracking":
        return render_tracking(args.write)
    if args.command == "sync-tracking":
        return sync_tracking(args.write)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
