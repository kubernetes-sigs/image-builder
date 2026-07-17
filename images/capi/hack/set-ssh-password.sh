#!/usr/bin/env bash

# Copyright 2024 The Kubernetes Authors.
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

set -o errexit
set -o nounset
set -o pipefail

PACKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../packer" && pwd -P)"

resolve_packer_var() {
  local key="$1"
  local default="$2"

  PACKER_DIR="$PACKER_DIR" python3 - "$key" "$default" <<'PY'
import json
import os
import shlex
import sys
from pathlib import Path

key = sys.argv[1]
value = sys.argv[2]
packer_dir = Path(os.environ["PACKER_DIR"])
cwd = Path.cwd()


def resolve_path(path):
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate
    if (cwd / candidate).exists():
        return cwd / candidate
    return packer_dir.parent / candidate


def load_var_file(path):
    global value
    candidate = resolve_path(path)
    if not candidate.is_file():
        return
    with candidate.open(encoding="utf-8") as var_file:
        data = json.load(var_file)
    if key in data:
        value = str(data[key])


def parse_flags():
    var_files = []
    vars_from_flags = []
    tokens = shlex.split(os.environ.get("PACKER_FLAGS", ""))
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in ("-var-file", "--var-file") and index + 1 < len(tokens):
            var_files.append(tokens[index + 1])
            index += 2
            continue
        if token.startswith("-var-file=") or token.startswith("--var-file="):
            var_files.append(token.split("=", 1)[1])
            index += 1
            continue
        if token in ("-var", "--var") and index + 1 < len(tokens):
            vars_from_flags.append(tokens[index + 1])
            index += 2
            continue
        if token.startswith("-var=") or token.startswith("--var="):
            vars_from_flags.append(token.split("=", 1)[1])
            index += 1
            continue
        index += 1
    return var_files, vars_from_flags


load_var_file(packer_dir / "config" / "common.json")

# Some Makefile targets (e.g. build-maas-ubuntu-2404-arm64) pass Packer a
# target-specific var-file (packer/maas/maas-ubuntu-2404-arm64.json) that can
# override values like ubuntu_repo/ubuntu_security_repo set in common.json
# (for example, using ports.ubuntu.com for arm64 builds). Load it here too so
# the rendered autoinstall data matches what Packer will actually use for
# this target. It can still be overridden by PACKER_VAR_FILES/PACKER_FLAGS
# below, same as it can on the Packer command line.
target_var_file = os.environ.get("PACKER_TARGET_VAR_FILE", "")
if target_var_file:
    load_var_file(target_var_file)

for var_file in shlex.split(os.environ.get("PACKER_VAR_FILES", "")):
    load_var_file(var_file)

flag_var_files, flag_vars = parse_flags()
for var_file in flag_var_files:
    load_var_file(var_file)
for item in flag_vars:
    if item.startswith(f"{key}="):
        value = item.split("=", 1)[1]

print(value)
PY
}

sed_escape_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

openssl_binary=openssl11
if ! command -v $openssl_binary >/dev/null 2>&1; then
  openssl_binary=openssl
  if ! command -v $openssl_binary >/dev/null 2>&1; then
    echo "openssl or openssl11 binary must be in \$PATH" 1>&2
    exit 1
  fi
fi

# Check if openssl version is atleast 1.1.1 to support SHA-512 algorithm
grep_flags="-Po"
if [[ "$OSTYPE" == "darwin"* ]]; then
  grep_flags="-Eo"
fi
current_openssl_version=$($openssl_binary version | grep $grep_flags "\d.\d.\d" | head -n1)
minimum_openssl_version="1.1.1"
if ! [ "$(printf '%s\n' "$minimum_openssl_version" "$current_openssl_version" | sort -V | head -n1)" = "$minimum_openssl_version" ]; then
  echo "OpenSSL version must be atleast $minimum_openssl_version, current OpenSSL version is $current_openssl_version" 1>&2
  exit 1
fi

export SSH_PASSWORD=${SSH_PASSWORD:-"$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16; echo)"}
SALT=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16; echo)
ENCRYPTED_SSH_PASSWORD=$($openssl_binary passwd -6 -salt "$SALT" -stdin <<< "$SSH_PASSWORD")
export ENCRYPTED_SSH_PASSWORD
export UBUNTU_REPO=${UBUNTU_REPO:-"$(resolve_packer_var ubuntu_repo "http://us.archive.ubuntu.com/ubuntu")"}
export UBUNTU_SECURITY_REPO=${UBUNTU_SECURITY_REPO:-"$(resolve_packer_var ubuntu_security_repo "http://security.ubuntu.com/ubuntu")"}

ssh_password_replacement="$(sed_escape_replacement "$SSH_PASSWORD")"
encrypted_ssh_password_replacement="$(sed_escape_replacement "$ENCRYPTED_SSH_PASSWORD")"
ubuntu_repo_replacement="$(sed_escape_replacement "$UBUNTU_REPO")"
ubuntu_security_repo_replacement="$(sed_escape_replacement "$UBUNTU_SECURITY_REPO")"

while IFS= read -r -d '' file; do
  if [ -f "${file%.*}" ]; then
    # HACK: There seems to be a case where this can actually
    # fail with the file not being found, leading to test failures.
    # If we fail to remove the file we just continue and assume
    # that the file was already removed.
    rm "${file%.*}" || true
  fi
  sed \
    -e "s|\$SSH_PASSWORD|$ssh_password_replacement|g" \
    -e "s|\$ENCRYPTED_SSH_PASSWORD|$encrypted_ssh_password_replacement|g" \
    -e "s|\$UBUNTU_REPO|$ubuntu_repo_replacement|g" \
    -e "s|\$UBUNTU_SECURITY_REPO|$ubuntu_security_repo_replacement|g" \
    "$file" | tee "${file%.*}"
done < <(find "$PACKER_DIR" -type f -name "*.tmpl" -print0)
