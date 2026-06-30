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

"""Resolve the Debian package revision for a Kubernetes release."""

from __future__ import annotations

import argparse
import re
import sys
import time
from urllib.error import URLError
from urllib.request import urlopen


REQUIRED_PACKAGES = ("kubeadm", "kubectl", "kubelet")
PACKAGES_URL = "https://pkgs.k8s.io/core:/stable:/v{series}/deb/Packages"


def load_packages(url: str, attempts: int = 3, backoff: float = 2.0) -> str:
    last_exc: URLError | None = None
    for attempt in range(1, attempts + 1):
        try:
            with urlopen(url, timeout=30) as response:
                return response.read().decode("utf-8")
        except URLError as exc:
            last_exc = exc
            if attempt < attempts:
                time.sleep(backoff * attempt)

    raise RuntimeError(
        f"failed to fetch {url} after {attempts} attempts: {last_exc}"
    ) from last_exc


def parse_packages(packages_text: str) -> dict[str, set[tuple[str, str]]]:
    package_versions: dict[str, set[tuple[str, str]]] = {}
    for stanza in packages_text.split("\n\n"):
        fields: dict[str, str] = {}
        for line in stanza.splitlines():
            if ": " not in line:
                continue
            key, value = line.split(": ", 1)
            fields[key] = value

        package = fields.get("Package")
        version = fields.get("Version")
        architecture = fields.get("Architecture")
        if package and version and architecture:
            package_versions.setdefault(package, set()).add((version, architecture))

    return package_versions


def version_sort_key(version: str) -> tuple[object, ...]:
    return tuple(
        int(part) if part.isdigit() else part
        for part in re.findall(r"\d+|\D+", version)
    )


def resolve_deb_version(
    kubernetes_version: str,
    package_versions: dict[str, set[tuple[str, str]]],
    architecture: str,
) -> str:
    candidates: set[str] | None = None
    prefix = f"{kubernetes_version}-"

    for package in REQUIRED_PACKAGES:
        versions = {
            version
            for version, package_architecture in package_versions.get(package, set())
            if package_architecture == architecture and version.startswith(prefix)
        }
        candidates = versions if candidates is None else candidates & versions

    if candidates:
        return sorted(candidates, key=version_sort_key)[-1]

    available = []
    for package in REQUIRED_PACKAGES:
        versions = sorted(
            version
            for version, package_architecture in package_versions.get(package, set())
            if package_architecture == architecture
        )
        available.append(f"{package}: {', '.join(versions) or 'none'}")

    raise ValueError(
        f"could not find a common Debian package version for Kubernetes "
        f"{kubernetes_version} on {architecture}; available versions: "
        f"{'; '.join(available)}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kubernetes_version", help="Kubernetes version, for example 1.36.2")
    parser.add_argument("--architecture", default="amd64", help="Debian architecture")
    args = parser.parse_args()

    kubernetes_version = args.kubernetes_version.removeprefix("v")
    series = ".".join(kubernetes_version.split(".")[:2])
    if not re.fullmatch(r"\d+\.\d+\.\d+", kubernetes_version):
        raise ValueError(f"invalid Kubernetes version: {args.kubernetes_version}")

    url = PACKAGES_URL.format(series=series)
    packages = parse_packages(load_packages(url))
    print(resolve_deb_version(kubernetes_version, packages, args.architecture))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
