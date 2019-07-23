#!/bin/bash

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

################################################################################
# usage: image-tools.sh [FLAGS]
#  This program ensures the tools required for building images are available
#  in the expected locations.
################################################################################

set -o errexit
set -o nounset
set -o pipefail

if ! command -v go >/dev/null 2>&1; then
  echo "Golang binary must be in \$PATH" 1>&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p hack/.bin && cd hack/.bin

HOSTOS=$(go env GOHOSTOS)
HOSTARCH=$(go env GOHOSTARCH)

checksum_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum    --ignore-missing -a 256 -c "${1}"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum --ignore-missing        -c "${1}"
  else
    echo "missing shasum tool" 1>&2
    return 1
  fi
}

ensure_ansible() {
  if [ -L "ansible" ]; then return; fi
  if _bin="$(command -v ansible 2>/dev/null)"; then
    ln -s "${_bin}" ansible; return
  fi
  if ! command -v python >/dev/null 2>&1; then
    echo "Python binary must be in \$PATH" 1>&2
    return 1
  fi
  if ! command -v pip >/dev/null 2>&1; then
    curl -L https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python get-pip.py --user
    rm -f get-pip.py
  fi
  _version="2.8.0"
  python -m pip install --user "ansible==${_version}"
  if _bin="$(command -v ansible 2>/dev/null)"; then
    ln -s "${_bin}" ansible; return
  fi
  echo "User's Python binary directory must bin in \$PATH" 1>&2
  return 1
}

ensure_jq() {
  if [ -L "jq" ]; then return; fi
  if [ -f "jq" ]; then
    { [ -x "jq" ] && return; } || rm -f "jq"
  fi
  if _bin="$(command -v jq 2>/dev/null)"; then
    ln -s "${_bin}" jq; return
  fi
  _version="1.6" # earlier versions don't follow the same OS/ARCH patterns
  case "${HOSTOS}" in
  linux)
    _binfile="jq-linux64"
    ;;
  darwin)
    _binfile="jq-osx-amd64"
    ;;
  *)
    echo "unsupported HOSTOS=${HOSTOS}" 1>&2
    return 1
    ;;
  esac
  _bin_url="https://github.com/stedolan/jq/releases/download/jq-${_version}/${_binfile}"
  curl -L "${_bin_url}" -o jq
  chmod 0755 jq
}

ensure_packer() {
  if [ -L "packer" ]; then return; fi
  if [ -f "packer" ]; then
    { [ -x "packer" ] && return; } || rm -f "packer"
  fi
  if _bin="$(command -v packer 2>/dev/null)"; then
    ln -s "${_bin}" packer; return
  fi
  _version="1.4.1"
  _chkfile="packer_${_version}_SHA256SUMS"
  _chk_url="https://releases.hashicorp.com/packer/${_version}/${_chkfile}"
  _zipfile="packer_${_version}_${HOSTOS}_${HOSTARCH}.zip"
  _zip_url="https://releases.hashicorp.com/packer/${_version}/${_zipfile}"
  curl -LO "${_chk_url}"
  curl -LO "${_zip_url}"
  checksum_sha256 "${_chkfile}"
  unzip "${_zipfile}"
  rm -f "${_chkfile}" "${_zipfile}"
}

ensure_packer_goss() {
  _binfile="${HOME}/.packer.d/plugins/packer-provisioner-goss"
  if [ -f "${_binfile}" ]; then
    { [ -x "${_binfile}" ] && return; } || rm -f "${_binfile}"
  fi
  _bin_dir="$(dirname "${_binfile}")"
  mkdir -p "${_bin_dir}" && cd "${_bin_dir}"
  case "${HOSTOS}" in
  linux)
    _sha256="28be39d0ddf9ad9c14e432818261abed2f2bd83257cfba213e19d5c59b710d03"
    ;;
  darwin)
    _sha256="7ae43b5dbd26a166c8673fc7299e91d1c2244c7d2b3b558ce04e2e53acfa6f88"
    ;;
  *)
    echo "unsupported HOSTOS=${HOSTOS}" 1>&2
    return 1
    ;;
  esac
  _version="0.3.0"
  _bin_url="https://github.com/YaleUniversity/packer-provisioner-goss/releases/download/v${_version}/packer-provisioner-goss-v${_version}-${HOSTOS}-${HOSTARCH}"
  curl -L "${_bin_url}" -o "${_binfile}"
  printf "%s *${_binfile}" "${_sha256}" >"${_binfile}.sha256"
  if ! checksum_sha256 "${_binfile}.sha256"; then
    _exit_code="${?}"
    rm -f "${_binfile}.sha256"
    return "${_exit_code}"
  fi
  rm -f "${_binfile}.sha256"
  chmod 0755 "${_binfile}"
}

#ensure_ansible
#ensure_jq
#ensure_packer
ensure_packer_goss
