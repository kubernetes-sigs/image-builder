#!/usr/bin/env bash

# Copyright 2019 The Kubernetes Authors.
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

[[ -n ${DEBUG:-} ]] && set -o xtrace

# **DO NOT** change the default Packer version unless it is available under
# MPL v2.0. HashiCorp relicensed Packer under the BUSL starting with v1.10.0,
# so 1.9.5 is the last MPL-2.0 release.
#
# Users who want to "bring their own Packer" can either:
#   * set PACKER_BIN=/path/to/packer to point at an existing binary, in which
#     case this script will leave it alone, or
#   * set PACKER_VERSION=x.y.z to download a different version into .local/bin
#     (combine with IB_ALLOW_ANY_PACKER=1 to accept a non-default Packer
#     already on PATH instead of "downgrading" it to the pinned version).
_default_version="1.9.5"
_version="${PACKER_VERSION:-${_default_version}}"
_allow_any="${IB_ALLOW_ANY_PACKER:-0}"

# Change directories to the parent directory of the one in which this
# script is located.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

source hack/utils.sh

# If the user has explicitly pointed us at a Packer binary, trust it.
if [ -n "${PACKER_BIN:-}" ]; then
  if [ ! -x "${PACKER_BIN}" ]; then
    echo "PACKER_BIN=${PACKER_BIN} is not an executable file" >&2
    exit 1
  fi
  echo "Using user-provided Packer at ${PACKER_BIN}"
  "${PACKER_BIN}" version || true
  exit 0
fi

# Some Linux distributions such as Fedora, RHEL, CentOS have a tool
# called packer installed by default at /usr/sbin, which will pass the
# command check, but is not the Packer we need for image builds. So we
# need to check if the Packer executable present on the machine is not
# that one. The default packer tool provided by cracklib does not have a
# version command and hangs indefinitely when the version command is
# invoked, so we are timeboxing it to 10 seconds. This shouldn't be the
# case with Packer installed from Hashicorp releases, which should give
# us a version number. This helps us distinguish the two Packer executables.

if (command -v packer) >/dev/null 2>&1; then
  echo "Packer is already installed, checking version..."
  # if it's not the hashicorp packer, fall through to install the pinned version
  if ! (timeout 10 packer version) >/dev/null 2>&1; then
    echo "unexpected packer found (no usable 'packer version' output)"
    echo "downloading hashicorp packer version v${_version}"
  else
    existing_packer_version=$(packer version | head -1 | cut -d 'v' -f 2; exit 0)
    echo "existing packer version: $existing_packer_version"
    if [ "$existing_packer_version" = "$_version" ]; then
      echo "Packer version $existing_packer_version is already installed"
      exit 0
    fi
    if [ "$_allow_any" = "1" ]; then
      echo "IB_ALLOW_ANY_PACKER=1 set; accepting existing packer ${existing_packer_version} (expected ${_version})"
      # Warn loudly if the user has opted into a post-MPL release.
      if [ "$(printf '%s\n1.10.0\n' "$existing_packer_version" | sort -V | head -n1)" != "$existing_packer_version" ] \
         || [ "$existing_packer_version" = "1.10.0" ]; then
        echo "WARNING: Packer >= 1.10.0 is licensed under the BUSL, not MPL-2.0."
        echo "         You are responsible for ensuring your use complies with that license."
      fi
      exit 0
    fi
    echo "unsupported packer version ($existing_packer_version) found"
    echo "current packer version: $existing_packer_version is not ${_version}"
    echo "Installing packer ${_version} into .local/bin (set IB_ALLOW_ANY_PACKER=1 to keep the existing one)"
  fi
fi

echo "Installing packer v${_version} in .local/bin"
mkdir -p .local/bin && cd .local/bin

SED="sed"
if command -v gsed >/dev/null; then
  SED="gsed"
fi
if ! (${SED} --version 2>&1 | grep -q GNU); then
  echo "!!! GNU sed is required.  If on macOS, use 'brew install gnu-sed'." >&2
  exit 1
fi

_chkfile="packer_${_version}_SHA256SUMS"
_chk_url="https://releases.hashicorp.com/packer/${_version}/${_chkfile}"
_zipfile="packer_${_version}_${HOSTOS}_${HOSTARCH}.zip"
_zip_url="https://releases.hashicorp.com/packer/${_version}/${_zipfile}"
curl -SsLO "${_chk_url}"
curl -SsLO "${_zip_url}"
${SED} -i -n "/${HOSTOS}_${HOSTARCH}/p" "${_chkfile}"
checksum_sha256 "${_chkfile}"
unzip -o "${_zipfile}"
rm -f "${_chkfile}" "${_zipfile}"
echo "'packer' has been installed to $(pwd), make sure this directory is in your \$PATH"
