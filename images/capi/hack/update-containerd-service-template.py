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

import argparse
import difflib
import json
import sys
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTAINERD_CONFIG = ROOT / "packer/config/containerd.json"
PPC64LE_CONTAINERD_CONFIG = ROOT / "packer/config/ppc64le/containerd.json"
CONTAINERD_SERVICE_TEMPLATE = (
    ROOT / "ansible/roles/containerd/templates/etc/systemd/system/containerd.service"
)
CONTAINERD_SERVICE_URL = (
    "https://raw.githubusercontent.com/containerd/containerd/"
    "refs/tags/v{version}/containerd.service"
)


def containerd_version(config_path):
    with config_path.open(encoding="utf-8") as config_file:
        config = json.load(config_file)

    version = config.get("containerd_version")
    if not version:
        raise ValueError(f"{config_path} does not set containerd_version")

    return version


def fetch_containerd_service(version):
    url = CONTAINERD_SERVICE_URL.format(version=version)
    with urllib.request.urlopen(url, timeout=30) as response:
        service = response.read().decode("utf-8")

    return url, service


def unified_diff(current, expected, expected_url):
    return difflib.unified_diff(
        current.splitlines(keepends=True),
        expected.splitlines(keepends=True),
        fromfile=str(CONTAINERD_SERVICE_TEMPLATE.relative_to(ROOT)),
        tofile=expected_url,
    )


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Updates or verifies the bundled containerd.service template "
            "against the pinned containerd version."
        )
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="update the bundled containerd.service template in place",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    version = containerd_version(CONTAINERD_CONFIG)
    ppc64le_version = containerd_version(PPC64LE_CONTAINERD_CONFIG)
    if version != ppc64le_version:
        print(
            "containerd_version differs between "
            f"{CONTAINERD_CONFIG.relative_to(ROOT)} ({version}) and "
            f"{PPC64LE_CONTAINERD_CONFIG.relative_to(ROOT)} ({ppc64le_version})",
            file=sys.stderr,
        )
        return 1

    url, expected = fetch_containerd_service(version)
    current = CONTAINERD_SERVICE_TEMPLATE.read_text(encoding="utf-8")

    if args.write:
        if current == expected:
            print(f"{CONTAINERD_SERVICE_TEMPLATE.relative_to(ROOT)} is already current")
        else:
            CONTAINERD_SERVICE_TEMPLATE.write_text(expected, encoding="utf-8")
            print(f"Updated {CONTAINERD_SERVICE_TEMPLATE.relative_to(ROOT)} from {url}")
        return 0

    if current == expected:
        print(
            f"{CONTAINERD_SERVICE_TEMPLATE.relative_to(ROOT)} matches "
            f"containerd v{version}"
        )
        return 0

    sys.stderr.writelines(unified_diff(current, expected, url))
    print(
        "Run `make update-containerd-service-template` from images/capi "
        "to refresh the bundled unit.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
