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

source hack/utils.sh

_version="1.1.0"
# SHA are for amd64 arch.
darwin_sha256="157b3d281717584ccdb0069e6d5eb90c27d758169960501b2d65902235d215b0"
linux_sha256="95efb49d7d9434c8aa8deff841ef3d83bd58988f592a72dfce46b684600f8d0a"
_bin_url="https://github.com/YaleUniversity/packer-provisioner-goss/releases/download/v${_version}/packer-provisioner-goss-v${_version}-${HOSTOS}-${HOSTARCH}"

_binfile="${HOME}/.packer.d/plugins/packer-provisioner-goss"
if [ -f "${_binfile}" ]; then
  { [ -x "${_binfile}" ] && exit 0; } || rm -f "${_binfile}"
fi
_bin_dir="$(dirname "${_binfile}")"
mkdir -p "${_bin_dir}" && cd "${_bin_dir}"
case "${HOSTOS}" in
linux)
  _sha256="${linux_sha256}"
  ;;
darwin)
  _sha256="${darwin_sha256}"
  ;;
*)
  echo "unsupported HOSTOS=${HOSTOS}" 1>&2
  return 1
  ;;
esac
curl -L "${_bin_url}" -o "${_binfile}"
printf "%s *${_binfile}" "${_sha256}" >"${_binfile}.sha256"
if ! checksum_sha256 "${_binfile}.sha256"; then
  _exit_code="${?}"
  rm -f "${_binfile}.sha256"
  exit "${_exit_code}"
fi
rm -f "${_binfile}.sha256"
chmod 0755 "${_binfile}"
