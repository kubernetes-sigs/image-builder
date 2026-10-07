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

r"""Render the Ubuntu autoinstall user-data of a single Packer build target.

Usage:

    render_ubuntu_autoinstall.py [--clean] --packer-template <template>
        -- <the exact -var/-var-file sequence given to packer>

Every qemu, maas and proxmox build/validate recipe in the Makefile calls this
script with the same argument vector it then passes to `packer build` or
`packer validate`, so the values resolved here are the values Packer resolves.
Precedence for legacy JSON templates, verified against Packer itself:

  1. the `variables` block of the Packer template (lowest precedence),
  2. every `-var-file`, in the order it appears on the command line,
     later files overriding earlier ones,
  3. every `-var`, which outranks every `-var-file` no matter where it
     appears, later `-var` flags overriding earlier ones.

Nested `{{user `name`}}` references inside a variable default are resolved,
because Packer resolves them too.

Rendering is per target and never global. The autoinstall directory is derived
from the target's own `http_directory`, `autoinstall_profile` and
`boot_command_prefix`, so aggregate targets such as `build-qemu-all` and
parallel `make -j` runs cannot render one target's user-data with another
target's variables.

`ubuntu_repo` and `ubuntu_security_repo` may carry credentials, so this script
never prints a variable value, and `--clean` undoes the substitution again when
the build recipe exits. It restores the file as set-ssh-password.sh wrote it,
kept alongside as `user-data.orig` while the build runs, because another target
can share the same autoinstall directory. Set KEEP_RENDERED_AUTOINSTALL=1 to
keep the rendered file for debugging.
"""

import argparse
import json
import os
import pathlib
import re
import sys


# images/capi, the directory the Makefile runs from and the directory the
# `http_directory` Packer variable is relative to.
CAPI_ROOT = pathlib.Path(__file__).resolve().parents[3]
PACKER_ROOT = CAPI_ROOT / "packer"

IMMUTABLE_DEFAULTS = {
    "immutable_data_partition": "false",
    "immutable_data_partition_fstype": "ext4",
    "immutable_data_partition_label": "CAPI-DATA",
    "immutable_data_partition_mount": "/.capi-data",
    "immutable_root_partition_size": "12884901888",
}

# Autoinstall placeholder -> Packer variable holding its value.
MIRROR_PLACEHOLDERS = (
    ("$UBUNTU_SECURITY_REPO", "ubuntu_security_repo"),
    ("$UBUNTU_REPO", "ubuntu_repo"),
)

# Placeholders that hack/set-ssh-password.sh substitutes. If one survives into
# the file this script writes, the installer would set a literal password and
# the image would be unusable, so refuse to write it.
PASSWORD_PLACEHOLDERS = ("$ENCRYPTED_SSH_PASSWORD", "$SSH_PASSWORD")

USER_VARIABLE = re.compile(r"\{\{\s*user\s+`([^`]+)`\s*\}\}")

# The autoinstall data source in boot_command_prefix, for example
# ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/24.04/'. The path
# component names the subdirectory of http_directory that Packer serves the
# user-data from.
BOOT_COMMAND_DATASOURCE = re.compile(
    r"s=https?://\{\{\s*\.HTTPIP\s*\}\}:\{\{\s*\.HTTPPort\s*\}\}/([^'\" ]*)"
)

# A mirror URL is pasted into YAML unquoted, so reject anything that could end
# the scalar or start a comment. The value is never echoed, it may hold a
# password.
MIRROR_URL = re.compile(r"\Ahttps?://[^\s'\"#]+\Z")


def load_json(path):
    with pathlib.Path(path).open(encoding="utf-8") as data:
        return json.load(data)


def template_variables(packer_template):
    """Return the defaults from a Packer JSON template's `variables` block.

    Falls back to the .tmpl the Makefile renders the template from, so the
    script also works before set-ssh-password.sh has run.
    """
    template = pathlib.Path(packer_template)
    if not template.is_absolute():
        template = CAPI_ROOT / template
    if not template.is_file():
        template = template.with_name(template.name + ".tmpl")
    variables = load_json(template).get("variables") or {}
    return {key: "" if value is None else str(value) for key, value in variables.items()}


def parse_packer_args(packer_args):
    """Split a Packer argument vector into its -var-file list and -var map."""
    var_files = []
    flag_vars = {}
    index = 0
    while index < len(packer_args):
        token = packer_args[index]
        value = None
        if token in ("-var-file", "--var-file") and index + 1 < len(packer_args):
            var_files.append(packer_args[index + 1])
            index += 2
            continue
        if token.startswith("-var-file=") or token.startswith("--var-file="):
            var_files.append(token.split("=", 1)[1])
        elif token in ("-var", "--var") and index + 1 < len(packer_args):
            value = packer_args[index + 1]
            index += 1
        elif token.startswith("-var=") or token.startswith("--var="):
            value = token.split("=", 1)[1]
        if value is not None and "=" in value:
            key, assigned = value.split("=", 1)
            flag_vars[key] = assigned
        index += 1
    return var_files, flag_vars


def resolve_values(packer_template, packer_args):
    """Resolve Packer variables exactly the way Packer resolves them."""
    values = template_variables(packer_template)

    var_files, flag_vars = parse_packer_args(packer_args)
    for var_file in var_files:
        path = pathlib.Path(var_file)
        if not path.is_absolute():
            path = CAPI_ROOT / path
        values.update({key: "" if val is None else str(val) for key, val in load_json(path).items()})

    # -var beats every -var-file regardless of its position on the command line.
    values.update(flag_vars)

    for key, fallback in IMMUTABLE_DEFAULTS.items():
        if not values.get(key, "").strip():
            values[key] = fallback
    return values


def interpolate(value, values):
    """Resolve `{{user `name`}}` references, as Packer does in variable defaults."""
    for _ in range(4):
        expanded = USER_VARIABLE.sub(lambda match: values.get(match.group(1), ""), value)
        if expanded == value:
            break
        value = expanded
    return value


def autoinstall_dir(values):
    """Return the directory Packer serves this target's user-data from."""
    if values.get("distro_name", "") != "ubuntu":
        return None

    http_directory = interpolate(values.get("http_directory", ""), values).strip()
    if not http_directory:
        return None

    profile = values.get("autoinstall_profile", "").strip().strip("/")
    if not profile:
        datasource = BOOT_COMMAND_DATASOURCE.search(values.get("boot_command_prefix", ""))
        profile = datasource.group(1).strip("/") if datasource else ""

    directory = (CAPI_ROOT / http_directory / profile).resolve()
    packer_root = PACKER_ROOT.resolve()
    if packer_root not in directory.parents:
        raise ValueError(f"resolved autoinstall directory is outside {packer_root}")
    return directory


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


def substitute_mirrors(content, values):
    for placeholder, variable in MIRROR_PLACEHOLDERS:
        if placeholder not in content:
            continue
        mirror = values.get(variable, "").strip()
        if not mirror:
            raise ValueError(f"{variable} is required to render {placeholder}")
        if not MIRROR_URL.fullmatch(mirror):
            # Deliberately without the value, it can contain a password.
            raise ValueError(
                f"{variable} must be an http(s) URL without whitespace, quotes or '#'"
            )
        content = content.replace(placeholder, mirror)
    return content


def substitute_immutable(content, values):
    if "${IMMUTABLE_AUTOINSTALL_ROOT_PARTITION_SIZE}" in content:
        validate_root_size(values["immutable_root_partition_size"])
        content = content.replace(
            "${IMMUTABLE_AUTOINSTALL_ROOT_PARTITION_SIZE}",
            str(values["immutable_root_partition_size"]),
        )
    if "${IMMUTABLE_AUTOINSTALL_DATA_PARTITION_CONFIG}" in content:
        content = content.replace(
            "${IMMUTABLE_AUTOINSTALL_DATA_PARTITION_CONFIG}",
            data_partition_config(values),
        )
    return content


def reject_password_placeholders(content):
    for placeholder in PASSWORD_PLACEHOLDERS:
        if placeholder in content:
            raise ValueError(
                f"{placeholder} is still unsubstituted, so the image would be "
                "unusable. Run hack/set-ssh-password.sh before rendering."
            )


def render_user_data(directory, values):
    template = directory / "user-data.tmpl"
    user_data = directory / "user-data"
    stash = directory / "user-data.orig"

    # A run killed between the write below and the restore in clean_user_data
    # leaves the stash behind. Put it back first so the stash always holds
    # set-ssh-password's output rather than a mirror-substituted file.
    if stash.is_file():
        os.replace(stash, user_data)

    # Prefer the already-rendered user-data over the raw .tmpl: set-ssh-password
    # runs first (see the build recipes in the Makefile) and substitutes the real
    # $ENCRYPTED_SSH_PASSWORD into user-data. Re-reading the pristine .tmpl here
    # would discard that substitution and leave the literal placeholder behind.
    if user_data.is_file():
        content = user_data.read_text(encoding="utf-8")
    elif template.is_file():
        content = template.read_text(encoding="utf-8")
    else:
        return None

    original = content
    content = substitute_mirrors(content, values)
    content = substitute_immutable(content, values)
    reject_password_placeholders(content)

    # Keep the pre-render file so clean_user_data can put it back. Another
    # target may share this directory (build-qemu-<name> and
    # build-kubevirt-<name> do) and set-ssh-password only runs once per make
    # invocation, so deleting it would leave that target rendering from the
    # pristine .tmpl.
    if user_data.is_file():
        stash.write_text(original, encoding="utf-8")
    user_data.write_text(content, encoding="utf-8")
    return user_data


def clean_user_data(directory):
    """Undo the mirror substitution so no credential survives the build.

    The pre-render file is restored when there is one, leaving exactly what
    set-ssh-password.sh wrote, so a target sharing this directory still finds
    the real build password in it.
    """
    template = directory / "user-data.tmpl"
    user_data = directory / "user-data"
    stash = directory / "user-data.orig"
    if stash.is_file():
        os.replace(stash, user_data)
        return "Restored", user_data
    if template.is_file() and user_data.is_file():
        user_data.unlink()
        return "Removed", user_data
    return None


def keep_rendered():
    return os.environ.get("KEEP_RENDERED_AUTOINSTALL", "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )


def split_argv(argv):
    """Split this script's own options from the Packer argument vector."""
    if "--" in argv:
        separator = argv.index("--")
        return argv[:separator], argv[separator + 1 :]
    return argv, []


def main(argv=None):
    script_args, packer_args = split_argv(sys.argv[1:] if argv is None else argv)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packer-template", required=True)
    parser.add_argument(
        "--clean",
        action="store_true",
        help="undo the substitution instead of writing it",
    )
    args = parser.parse_args(script_args)

    values = resolve_values(args.packer_template, packer_args)
    directory = autoinstall_dir(values)
    if directory is None or not directory.is_dir():
        return

    if args.clean:
        if keep_rendered():
            return
        cleaned = clean_user_data(directory)
        if cleaned is not None:
            verb, path = cleaned
            print(f"{verb} rendered Ubuntu autoinstall user-data: {relative(path)}")
        return

    rendered = render_user_data(directory, values)
    if rendered is not None:
        print(f"Rendered Ubuntu autoinstall user-data: {relative(rendered)}")


def relative(path):
    try:
        return path.relative_to(CAPI_ROOT)
    except ValueError:
        return path


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        # Cleanup must never turn a successful build into a failed one.
        if "--clean" in sys.argv:
            print(f"render_ubuntu_autoinstall.py: {err}", file=sys.stderr)
            sys.exit(0)
        print(f"render_ubuntu_autoinstall.py: {err}", file=sys.stderr)
        sys.exit(1)
