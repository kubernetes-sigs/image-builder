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
# usage: image-ssh.sh BUILD_DIR [SSH_USER]
#  This program uses SSH to connect to an image running locally in VMware
#  Workstation or VMware Fusion.
################################################################################

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

if [ "${#}" -lt "1" ]; then
  echo "usage: ${0} BUILD_DIR [SSH_USER]" 1>&2
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

# Get the SSH user.
SSH_USER="${SSH_USER:-${2-}}"
if [ -z "${SSH_USER}" ]; then
  SSH_USER=builder
fi
if [ -z "${SSH_USER}" ]; then
  echo "SSH_USER is required" 1>&2
  exit 1
fi

# Get the VM's IP address.
IP_ADDR="$(vmrun getGuestIPAddress "${VMX_FILE}")"

# SSH into the VM with the provided user.
SSH_KEY="$(dirname "${BASH_SOURCE[0]}")/../cloudinit/id_rsa.capi"
echo "image-ssh: ssh -i ${SSH_KEY} ${SSH_USER}@${IP_ADDR}"
exec ssh -o UserKnownHostsFile=/dev/null -i "${SSH_KEY}" "${SSH_USER}"@"${IP_ADDR}"
