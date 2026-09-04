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
from typing import Any, NamedTuple


sys.dont_write_bytecode = True

CAPI_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = CAPI_ROOT.parents[1]
MATRIX_FILE = CAPI_ROOT / "packer/config/kubernetes-version-matrix.yaml"
LATEST_FILE = CAPI_ROOT / "packer/config/kubernetes-version-latest.yaml"
TRACKING_DIR = CAPI_ROOT / "packer/config/kubernetes-version-dependencies"
TRACKING_FILE_NAME = ".pre-commit-config.yaml"
DEPENDABOT_FILE = REPO_ROOT / ".github/dependabot.yml"
DEPENDABOT_ECOSYSTEM = "pre-commit"
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


class TrackedRepo(NamedTuple):
    """A git repository Dependabot follows through a pre-commit ``rev``.

    ``unprefixed`` marks the matrix keys that store the upstream release tag
    without its leading ``v``.
    """

    repo: str
    entry_key: str
    unprefixed: bool


TRACKED_REPOS = (
    TrackedRepo("https://github.com/containerd/containerd", "containerd_version", True),
    TrackedRepo(
        "https://github.com/containernetworking/plugins", "kubernetes_cni_semver", False
    ),
    TrackedRepo("https://github.com/opencontainers/runc", "runc_version", True),
    TrackedRepo("https://github.com/kubernetes/kubernetes", "kubernetes_semver", False),
    TrackedRepo("https://github.com/kubernetes-sigs/cri-tools", "crictl_version", True),
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
    """Refresh the pins one selector resolves from upstream release metadata.

    Only the Kubernetes version fields, the kubernetes-cni package versions and
    crictl are refreshed here. ``containerd_version``, ``runc_version`` and
    ``kubernetes_cni_semver`` are deliberately carried over from ``current``:
    Dependabot tracks each of them through a pre-commit ``rev``, and the CNI
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


def tracking_config_path(selector: str) -> Path:
    return TRACKING_DIR / tracking_selector_name(selector) / TRACKING_FILE_NAME


def tracking_rev(tracked: TrackedRepo, entry: dict[str, Any]) -> str:
    """Return the git tag ``tracked`` is pinned to in ``entry``."""
    value = str(entry[tracked.entry_key])
    return f"v{value}" if tracked.unprefixed else value


def tracking_value(tracked: TrackedRepo, rev: str) -> str:
    """Return the matrix value a git tag maps back to."""
    return rev.removeprefix("v") if tracked.unprefixed else rev


def render_tracking_config(selector: str, entry: dict[str, Any]) -> str:
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
        f"# Dependabot tracking manifest for the {selector} dependency set.",
        "# Dependabot's pre-commit updater follows the git tags of the repositories",
        "# below and rewrites the matching rev. The pre-commit tool never runs these",
        "# hooks. Regenerate with:",
        "#   images/capi/hack/kubernetes-version-matrix.py render-tracking --write",
        "repos:",
    ]
    for tracked in TRACKED_REPOS:
        lines.append(f"  - repo: {tracked.repo}")
        lines.append(f"    rev: {tracking_rev(tracked, entry)}")
        lines.append("    hooks: []")
    return "\n".join(lines) + "\n"


def tracking_entries(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any]
) -> list[tuple[str, dict[str, Any]]]:
    entries = [
        (selector, release_pins[selector])
        for selector in sorted(release_pins, key=version_sort_key)
    ]
    entries.append(("latest", latest))
    return entries


def render_tracking_configs(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any]
) -> dict[Path, str]:
    return {
        tracking_config_path(selector): render_tracking_config(selector, entry)
        for selector, entry in tracking_entries(release_pins, latest)
    }


def read_tracking_config(selector: str) -> dict[str, str]:
    """Return the rev every repository in one tracking manifest is pinned to.

    Only ``repo`` and ``rev`` are read, so Dependabot may reorder or reformat
    the manifest as long as the pairs survive.
    """
    path = tracking_config_path(selector)
    if not path.exists():
        raise FileNotFoundError(f"{path} does not exist")

    revs: dict[str, str] = {}
    for repo in yq_json(path, ".repos") or []:
        if isinstance(repo, dict) and "repo" in repo and "rev" in repo:
            revs[str(repo["repo"])] = str(repo["rev"])
    return revs


def tracking_issues(selector: str, entry: dict[str, Any]) -> list[str]:
    """Report why a tracking manifest does not match the matrix; empty when it does."""
    path = tracking_config_path(selector)
    if not path.exists():
        return [f"{path}: missing Dependabot tracking manifest"]

    revs = read_tracking_config(selector)
    issues = []
    for tracked in TRACKED_REPOS:
        expected = tracking_rev(tracked, entry)
        actual = revs.pop(tracked.repo, None)
        if actual is None:
            issues.append(f"{path}: {tracked.repo} is not tracked")
        elif actual != expected:
            issues.append(f"{path}: {tracked.repo} rev is {actual}, expected {expected}")
    issues.extend(f"{path}: unexpected repository {repo}" for repo in sorted(revs))
    return issues


def unexpected_tracking_files(expected_paths: set[Path]) -> list[str]:
    if not TRACKING_DIR.exists():
        return []
    return [
        f"{path}: unexpected Dependabot tracking file"
        for path in sorted(TRACKING_DIR.rglob("*"))
        if path.is_file() and path not in expected_paths
    ]


def dependabot_directory(selector: str) -> str:
    directory = TRACKING_DIR / tracking_selector_name(selector)
    return f"/{directory.relative_to(REPO_ROOT).as_posix()}"


def ignore_bound(selector: str, tracked: TrackedRepo, entry: dict[str, Any]) -> str:
    """Return the ignore range that holds one repository to the selector's pin policy.

    A release pin is held below the next minor of its pinned version, the
    rolling latest entry below the next major. The range is a single clause on
    purpose: Dependabot::PreCommit::Requirement passes the whole string to
    Gem::Requirement without splitting on commas, so a two-clause range raises
    Gem::Requirement::BadRequirementError and fails the update job.
    """
    major, minor = str(entry[tracked.entry_key]).removeprefix("v").split(".")[:2]
    if selector == "latest":
        return f">= {int(major) + 1}.0.0"
    return f">= {major}.{int(minor) + 1}.0"


def expected_dependabot_ignores(selector: str, entry: dict[str, Any]) -> dict[str, str]:
    return {
        tracked.repo: ignore_bound(selector, tracked, entry) for tracked in TRACKED_REPOS
    }


def dependabot_precommit_updates() -> list[tuple[list[str], dict[str, Any]]]:
    """Return the directories and body of every pre-commit entry in dependabot.yml."""
    config = yq_json(DEPENDABOT_FILE, ".")
    updates = []
    for update in config.get("updates") or []:
        if update.get("package-ecosystem") != DEPENDABOT_ECOSYSTEM:
            continue
        directories = list(update.get("directories") or [])
        if directory := update.get("directory"):
            directories.append(directory)
        updates.append((directories, update))
    return updates


def dependabot_ignore_issues(
    directory: str, selector: str, entry: dict[str, Any], update: dict[str, Any]
) -> list[str]:
    """Check one entry ignores exactly the ranges the pin policy implies."""
    issues = []
    conditions: dict[str, list[str]] = {}
    for condition in update.get("ignore") or []:
        name = str(condition.get("dependency-name"))
        if condition.get("update-types"):
            issues.append(
                f"{DEPENDABOT_FILE}: {directory} ignores {name} by update-type, which "
                "dependabot-core cannot apply to a pre-commit dependency"
            )
        conditions.setdefault(name, []).extend(condition.get("versions") or [])

    for repo, bound in expected_dependabot_ignores(selector, entry).items():
        if conditions.pop(repo, None) != [bound]:
            issues.append(
                f'{DEPENDABOT_FILE}: {directory} must ignore {repo} versions [ "{bound}" ]'
            )
    issues.extend(
        f"{DEPENDABOT_FILE}: {directory} ignores {name}, which the matrix does not track"
        for name in sorted(conditions)
    )
    return issues


def dependabot_issues(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any]
) -> list[str]:
    """Check dependabot.yml holds every tracking directory to its pin policy.

    Every directory needs its own entry, named exactly, because the ignore
    ranges differ per directory and a glob cannot carry per-directory ranges.
    """
    issues = []
    by_directory: dict[str, dict[str, Any]] = {}
    for directories, update in dependabot_precommit_updates():
        for directory in directories:
            if directory in by_directory:
                issues.append(
                    f"{DEPENDABOT_FILE}: {directory} has more than one pre-commit entry"
                )
            by_directory[directory] = update

    for selector, entry in tracking_entries(release_pins, latest):
        directory = dependabot_directory(selector)
        update = by_directory.pop(directory, None)
        if update is None:
            issues.append(f"{DEPENDABOT_FILE}: no pre-commit entry for {directory}")
            continue
        issues.extend(dependabot_ignore_issues(directory, selector, entry, update))
    issues.extend(
        f"{DEPENDABOT_FILE}: pre-commit entry {directory!r} is not a tracking directory"
        for directory in sorted(by_directory)
    )
    return issues


def pin_policy_errors(
    selector: str, current: dict[str, Any], values: dict[str, str]
) -> list[str]:
    """Reject rev changes that are wider than the selector's pin policy.

    The explicit ``ignore`` ranges in dependabot.yml are the first guard and
    keep Dependabot from proposing such a change at all. This is the second:
    the ranges are only as good as their last regeneration, and a rev can also
    reach the tree by hand, so a release pin takes patch updates only and the
    rolling latest entry takes everything below a major bump.
    """
    segments = 1 if selector == "latest" else 2
    errors = []
    for tracked in TRACKED_REPOS:
        before = str(current.get(tracked.entry_key, "")).removeprefix("v")
        after = values[tracked.entry_key].removeprefix("v")
        if not before or before.split(".")[:segments] == after.split(".")[:segments]:
            continue
        errors.append(
            f"{selector}: {tracked.repo} moved from {before} to {after}, which the "
            f"{selector} pin policy does not allow"
        )
    return errors


def entry_from_tracking(selector: str, current: dict[str, Any]) -> dict[str, Any]:
    """Fold the revs Dependabot maintains back into one matrix entry.

    The kubernetes-cni package versions are not touched. They pin the distro
    package, which is versioned separately from the CNI plugins tarball that
    ``kubernetes_cni_semver`` selects.
    """
    revs = read_tracking_config(selector)
    missing = [tracked.repo for tracked in TRACKED_REPOS if tracked.repo not in revs]
    if missing:
        raise ValueError(
            f"{selector}: tracking manifest missing repositories: {', '.join(missing)}"
        )

    values = {
        tracked.entry_key: tracking_value(tracked, revs[tracked.repo])
        for tracked in TRACKED_REPOS
    }
    if errors := pin_policy_errors(selector, current, values):
        raise ValueError("; ".join(errors))

    kubernetes_semver = values["kubernetes_semver"]
    kubernetes_version = kubernetes_semver.removeprefix("v")
    kubernetes_minor = ".".join(kubernetes_version.split(".")[:2])
    if selector != "latest" and kubernetes_minor != selector:
        raise ValueError(
            f"{selector}: tracking manifest points to Kubernetes {kubernetes_minor}, "
            f"expected {selector}"
        )

    deb_version = current.get("kubernetes_deb_version")
    if current.get("kubernetes_rpm_version") != kubernetes_version or not deb_version:
        deb_version = resolve_kubernetes_deb_version(kubernetes_version)

    updated = dict(current)
    updated.update(values)
    updated.update(
        {
            "kubernetes_deb_version": deb_version,
            "kubernetes_rpm_version": kubernetes_version,
            "kubernetes_series": f"v{kubernetes_minor}",
        }
    )
    return {key: updated[key] for key in REQUIRED_KEYS}


def expected_files(
    release_pins: dict[str, dict[str, Any]], latest: dict[str, Any]
) -> dict[Path, str]:
    return {
        MATRIX_FILE: render_release_matrix_yaml(release_pins),
        LATEST_FILE: render_latest_yaml(latest),
        **render_tracking_configs(release_pins, latest),
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

    expected_paths = set()
    for selector, entry in tracking_entries(release_pins, latest):
        expected_paths.add(tracking_config_path(selector))
        errors.extend(tracking_issues(selector, entry))
    errors.extend(unexpected_tracking_files(expected_paths))
    errors.extend(dependabot_issues(release_pins, latest))

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


def render_tracking(write: bool) -> int:
    release_pins, latest = load_matrix()
    changed = apply_expected_files(render_tracking_configs(release_pins, latest), write)

    if changed and not write:
        print(
            "Dependabot tracking manifests do not match the matrix; rerun with --write",
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
    update_parser.add_argument("--write", action="store_true", help="write refreshed files")

    render_tracking_parser = subparsers.add_parser(
        "render-tracking", help="regenerate the Dependabot tracking manifests from the matrix"
    )
    render_tracking_parser.add_argument(
        "--write", action="store_true", help="write the tracking manifests"
    )

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
    if args.command == "render-tracking":
        return render_tracking(args.write)
    if args.command == "sync-tracking":
        return sync_tracking(args.write)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
