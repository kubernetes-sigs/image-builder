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
import json
import os
import pathlib
import re
import shlex
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
IMMUTABLE_DEFAULTS = {
    "immutable_data_partition": "false",
    "immutable_data_partition_fstype": "ext4",
    "immutable_data_partition_label": "CAPI-DATA",
    "immutable_data_partition_mount": "/.capi-data",
    "immutable_root_partition_size": "12884901888",
}


def load_json(path):
    with path.open(encoding="utf-8") as data:
        return json.load(data)


def parse_packer_flags(flags):
    values = {}
    var_files = []
    tokens = shlex.split(flags or "")
    index = 0
    while index < len(tokens):
        token = tokens[index]
        value = None
        if token in ("-var", "--var") and index + 1 < len(tokens):
            index += 1
            value = tokens[index]
        elif token.startswith("-var=") or token.startswith("--var="):
            value = token.split("=", 1)[1]
        elif token in ("-var-file", "--var-file") and index + 1 < len(tokens):
            index += 1
            var_files.append(tokens[index])
        elif token.startswith("-var-file=") or token.startswith("--var-file="):
            var_files.append(token.split("=", 1)[1])

        if value and "=" in value:
            key, raw = value.split("=", 1)
            values[key] = raw
        index += 1
    return values, var_files


def as_bool(value):
    return str(value).strip().lower() in ("1", "true", "yes", "on")


def validate_label(label):
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,16}", label):
        raise ValueError(
            "immutable_data_partition_label must be 1-16 characters of "
            "letters, digits, '_', '.', or '-'"
        )


def validate_mount(mount):
    if not mount.startswith("/") or mount in ("/", "/boot", "/boot/efi"):
        raise ValueError("immutable_data_partition_mount must be an absolute non-root path")
    if re.search(r"\s", mount):
        raise ValueError("immutable_data_partition_mount must not contain whitespace")


def validate_root_size(root_size):
    if not re.fullmatch(r"[1-9][0-9]*", str(root_size)):
        raise ValueError("immutable_root_partition_size must be a positive byte count")


def data_partition_config(values):
    if not as_bool(values["immutable_data_partition"]):
        return ""

    label = str(values["immutable_data_partition_label"])
    mount = str(values["immutable_data_partition_mount"])
    fstype = str(values["immutable_data_partition_fstype"])
    validate_label(label)
    validate_mount(mount)
    if fstype != "ext4":
        raise ValueError("immutable_data_partition_fstype currently supports only ext4")

    return f"""\
      - type: partition
        id: partition-data
        device: disk-0
        size: -1
        number: 2
        preserve: false
        flag: ''
      - type: format
        id: format-data
        volume: partition-data
        fstype: {fstype}
        label: {label}
        preserve: false
      - type: mount
        id: mount-data
        device: format-data
        path: {mount}"""


def render_user_data(var_file, values):
    profile = values.get("autoinstall_profile")
    distro = values.get("distro_name")
    if distro != "ubuntu" or not profile:
        return

    profile_dir = ROOT / "qemu" / "linux" / "ubuntu" / "http" / str(profile)
    user_data = profile_dir / "user-data"
    template = profile_dir / "user-data.tmpl"
    if template.exists():
        content = template.read_text(encoding="utf-8")
    elif user_data.exists():
        content = user_data.read_text(encoding="utf-8")
    else:
        raise FileNotFoundError(f"{user_data} or {template} is required")

    validate_root_size(values["immutable_root_partition_size"])
    content = content.replace(
        "${IMMUTABLE_AUTOINSTALL_ROOT_PARTITION_SIZE}",
        str(values["immutable_root_partition_size"]),
    )
    content = content.replace(
        "${IMMUTABLE_AUTOINSTALL_DATA_PARTITION_CONFIG}",
        data_partition_config(values),
    )
    user_data.write_text(content, encoding="utf-8")
    print(f"Rendered Ubuntu autoinstall user-data for {var_file.name}: {user_data}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("var_file", type=pathlib.Path)
    parser.add_argument("--extra-var-file", action="append", default=[], type=pathlib.Path)
    args = parser.parse_args()

    values = dict(IMMUTABLE_DEFAULTS)
    values.update(load_json(args.var_file))

    packer_values, packer_var_files = parse_packer_flags(os.environ.get("PACKER_FLAGS", ""))
    for var_file in [pathlib.Path(path) for path in packer_var_files] + args.extra_var_file:
        values.update(load_json(var_file))
    values.update(packer_values)

    render_user_data(args.var_file, values)


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print(f"render_ubuntu_autoinstall.py: {err}", file=sys.stderr)
        sys.exit(1)
