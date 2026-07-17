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
import re
import sys
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTAINERD_CONFIG = ROOT / "packer/config/containerd.json"
PPC64LE_CONTAINERD_CONFIG = ROOT / "packer/config/ppc64le/containerd.json"
CONTAINERD_SERVICE_TEMPLATE = (
    ROOT / "ansible/roles/containerd/templates/etc/systemd/system/containerd.service"
)
CONTAINERD_DEFAULTS = ROOT / "ansible/roles/containerd/defaults/main.yml"
CONTAINERD_SERVICE_TEMPLATE_VERSION_RE = re.compile(
    r'^containerd_service_template_version:\s*"(?P<version>[^"]*)"', re.MULTILINE
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


def _match_service_template_version(defaults_path, text):
    match = CONTAINERD_SERVICE_TEMPLATE_VERSION_RE.search(text)
    if not match:
        raise ValueError(
            f"{defaults_path} does not set containerd_service_template_version"
        )
    return match


def service_template_version(defaults_path):
    text = defaults_path.read_text(encoding="utf-8")
    return _match_service_template_version(defaults_path, text).group("version")


def write_service_template_version(defaults_path, version):
    text = defaults_path.read_text(encoding="utf-8")
    match = _match_service_template_version(defaults_path, text)
    if match.group("version") == version:
        return False

    start, end = match.span("version")
    defaults_path.write_text(text[:start] + version + text[end:], encoding="utf-8")
    return True


def unified_diff(current, expected, fromfile, tofile):
    return difflib.unified_diff(
        current.splitlines(keepends=True),
        expected.splitlines(keepends=True),
        fromfile=fromfile,
        tofile=tofile,
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


def resolve_expected_service(version, ppc64le_version):
    """Fetches the upstream containerd.service unit for the pinned generic
    containerd version and, when architecture pins have diverged, checks
    that the upstream units for both pinned versions are equivalent.

    Returns (url, service) for the generic pin on success, or None if the
    diverging pins produce non-equivalent upstream units (the caller should
    treat that as a hard failure).
    """
    url, expected = fetch_containerd_service(version)

    if ppc64le_version == version:
        return url, expected

    ppc64le_url, ppc64le_expected = fetch_containerd_service(ppc64le_version)
    if ppc64le_expected != expected:
        print(
            "containerd_version differs between "
            f"{CONTAINERD_CONFIG.relative_to(ROOT)} ({version}) and "
            f"{PPC64LE_CONTAINERD_CONFIG.relative_to(ROOT)} ({ppc64le_version}), "
            "and their upstream containerd.service units are not equivalent:",
            file=sys.stderr,
        )
        sys.stderr.writelines(
            unified_diff(expected, ppc64le_expected, url, ppc64le_url)
        )
        print(
            "The bundled containerd.service template can only track one "
            "pinned version. Either re-pin both architectures to the same "
            "containerd_version, or set containerd_service_url explicitly "
            "for the architecture pinned to the diverging version.",
            file=sys.stderr,
        )
        return None

    print(
        "containerd_version differs between "
        f"{CONTAINERD_CONFIG.relative_to(ROOT)} ({version}) and "
        f"{PPC64LE_CONTAINERD_CONFIG.relative_to(ROOT)} ({ppc64le_version}), "
        "but their upstream containerd.service units are equivalent; "
        "continuing with the generic pin.",
        file=sys.stderr,
    )
    return url, expected


def main():
    args = parse_args()

    version = containerd_version(CONTAINERD_CONFIG)
    ppc64le_version = containerd_version(PPC64LE_CONTAINERD_CONFIG)

    resolved = resolve_expected_service(version, ppc64le_version)
    if resolved is None:
        return 1
    url, expected = resolved

    current = CONTAINERD_SERVICE_TEMPLATE.read_text(encoding="utf-8")

    if args.write:
        changed = False
        if current == expected:
            print(f"{CONTAINERD_SERVICE_TEMPLATE.relative_to(ROOT)} is already current")
        else:
            CONTAINERD_SERVICE_TEMPLATE.write_text(expected, encoding="utf-8")
            print(f"Updated {CONTAINERD_SERVICE_TEMPLATE.relative_to(ROOT)} from {url}")
            changed = True

        if write_service_template_version(CONTAINERD_DEFAULTS, version):
            print(
                f"Updated containerd_service_template_version in "
                f"{CONTAINERD_DEFAULTS.relative_to(ROOT)} to {version}"
            )
            changed = True

        if not changed:
            print("Nothing to update.")
        return 0

    template_version = service_template_version(CONTAINERD_DEFAULTS)
    problems = []

    if current != expected:
        problems.append("template_mismatch")

    if template_version != version:
        problems.append("pin_mismatch")

    if not problems:
        print(
            f"{CONTAINERD_SERVICE_TEMPLATE.relative_to(ROOT)} matches "
            f"containerd v{version}"
        )
        return 0

    if "template_mismatch" in problems:
        sys.stderr.writelines(
            unified_diff(
                current,
                expected,
                str(CONTAINERD_SERVICE_TEMPLATE.relative_to(ROOT)),
                url,
            )
        )

    if "pin_mismatch" in problems:
        print(
            "containerd_service_template_version in "
            f"{CONTAINERD_DEFAULTS.relative_to(ROOT)} ({template_version}) does "
            f"not match the pinned containerd_version ({version}) in "
            f"{CONTAINERD_CONFIG.relative_to(ROOT)}.",
            file=sys.stderr,
        )

    print(
        "Run `make update-containerd-service-template` from images/capi "
        "to refresh the bundled unit.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
