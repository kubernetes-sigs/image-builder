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

source hack/utils.sh

# SHA are for amd64 arch.
_version="3.0.3"
darwin_sha256="279a33eb3102385ff3c0577b0d35c4f218e54dddb53e549c626aed1741c93f34"
linux_sha256="687fda0873028fb60443339f47412856d08eea1007d274bda25078df426b21bc"
_bin_url="https://github.com/YaleUniversity/packer-provisioner-goss/releases/download/v${_version}/packer-provisioner-goss-v${_version}-${HOSTOS}-${HOSTARCH}.tar.gz"
_tarfile="${HOME}/.packer.d/plugins/packer-provisioner-goss.tar.gz"
_binfile="${HOME}/.packer.d/plugins/packer-provisioner-goss"

# Get a shasum for right OS's binary
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

# Check if current binary is latest
if [ -f "${_binfile}" ]; then
  current_shasum=$(get_shasum "${_binfile}")
  if [ "$current_shasum" != "$_sha256" ]; then
    echo "Wrong version of binary present."
  else
    echo "Right version of binary present"
    # Check if binary is executable.
    # If not, delete it and proceed. If it is executable, exit 0
    { [ -x "${_binfile}" ] && exit 0; } || rm -f "${_binfile}"
  fi
fi

# download binary, verify shasum, make it executable and clean up trash files.
_bin_dir="$(dirname "${_tarfile}")"
mkdir -p "${_bin_dir}" && cd "${_bin_dir}"
curl -SsL "${_bin_url}" -o "${_tarfile}"
tar -C "${_bin_dir}" -xzf "${_tarfile}"
rm "${_tarfile}"
printf "%s *${_binfile}" "${_sha256}" >"${_binfile}.sha256"
if ! checksum_sha256 "${_binfile}.sha256"; then
  _exit_code="${?}"
  rm -f "${_binfile}.sha256"
  exit "${_exit_code}"
fi
rm -f "${_binfile}.sha256"
chmod 0755 "${_binfile}"
