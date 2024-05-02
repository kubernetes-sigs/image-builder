#!/usr/bin/env bash

# Copyright 2022 The Kubernetes Authors.
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

source hack/utils.sh

SED="sed"
if command -v gsed >/dev/null; then
  SED="gsed"
fi
if ! (${SED} --version 2>&1 | grep -q GNU); then
  echo "!!! GNU sed is required.  If on macOS, use 'brew install gnu-sed'." >&2
  exit 1
fi

_version="0.2.4"
_chkfile="packer-plugin-powervs_v${_version}_SHA256SUMS"
_chk_url="https://github.com/ppc64le-cloud/packer-plugin-powervs/releases/download/v${_version}/${_chkfile}"
_bin_url="https://github.com/ppc64le-cloud/packer-plugin-powervs/releases/download/v${_version}/packer-plugin-powervs_v${_version}_x5.0_${HOSTOS}_${HOSTARCH}.zip"
_zipfile="${HOME}/.packer.d/plugins/packer-plugin-powervs_v${_version}_x5.0_${HOSTOS}_${HOSTARCH}.zip"
_binfile="${HOME}/.packer.d/plugins/packer-plugin-powervs_v${_version}_x5.0_${HOSTOS}_${HOSTARCH}"
_powervs_bin="${HOME}/.packer.d/plugins/packer-plugin-powervs"

_bin_dir="$(dirname "${_zipfile}")"
mkdir -p "${_bin_dir}" && cd "${_bin_dir}"
curl -SsLO "${_chk_url}"
curl -SsLO "${_bin_url}"
${SED} -i -n "/${HOSTOS}_${HOSTARCH}/p" "${_chkfile}"
checksum_sha256 "${_chkfile}"
rm -f "${_chkfile}"
unzip -o "${_zipfile}"
rm "${_zipfile}"
chmod 0755 "${_binfile}"
mv "${_binfile}" "${_powervs_bin}"
