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
# usage: image-post-create-config.sh BUILD_DIR
#  This program runs after a new image is created and:
#    1. Creates a snapshot of the image named "new"
#    2. Modifies the image to use 2 vCPU
#    3. Creates a snapshot of the image named "2cpu"
#    4. Attaches the ISO build/images/cloudinit/cidata.iso
################################################################################

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

if [ "${#}" -ne "1" ]; then
  echo "usage: ${0} BUILD_DIR" 1>&2
  exit 1
fi

VM_RUN="${VM_RUN:-$(command -v vmrun 2>/dev/null)}"
if [ ! -e "${VM_RUN}" ] || [ ! -x "${VM_RUN}" ]; then
  echo "vmrun must be in \$PATH or specified by \$VM_RUN" 1>&2
  exit 1
fi
VM_RUN_DIR="$(dirname "${VM_RUN}")"
export PATH="${VM_RUN_DIR}:${PATH}"

# Get the path of the VMX file.
VMX_FILE=$(/bin/ls "${1-}"/*.vmx)

create_snapshot() {
  snapshots="$(vmrun listSnapshots "${VMX_FILE}" 2>/dev/null)"
  if [[ ${snapshots} = *${1-}* ]]; then
    echo "image-post-create-config: skip snapshot '${1-}'; already exists"
  else
    echo "image-post-create-config: create snapshot '${1-}'"
    vmrun snapshot "${VMX_FILE}" "${1-}"
  fi
}

create_snapshot new

if grep -q 'numvcpus = "2"' "${VMX_FILE}"; then
  echo "image-post-create-config: skipping cpu update; already 2"
else
  echo "image-post-create-config: update cpu count to 2"
  sed -i.bak -e 's/numvcpus = "1"/numvcpus = "2"/' -e 's/cpuid.corespersocket = "1"/cpuid.corespersocket = "2"/' "${VMX_FILE}"
  create_snapshot 2cpu
fi

if grep -q 'guestinfo.userdata' "${VMX_FILE}"; then
  echo "image-post-create-config: skipping cloud-init data; already exists"
else
  echo "image-post-create-config: insert cloud-init data"
  CIDATA_DIR="$(dirname "${BASH_SOURCE[0]}")/../cloudinit"
  cat <<EOF >>"${VMX_FILE}"
guestinfo.userdata = "$({ base64 -w0 || base64; } 2>/dev/null <"${CIDATA_DIR}/user-data")"
guestinfo.userdata.encoding = "base64"
guestinfo.metadata = "$({ base64 -w0 || base64; } 2>/dev/null <"${CIDATA_DIR}/meta-data")"
guestinfo.metadata.encoding = "base64"
EOF
  create_snapshot cloudinit
fi
