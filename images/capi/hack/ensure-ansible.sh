#!/usr/bin/env bash

# Copyright 2020 The Kubernetes Authors.
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

# Change directories to the parent directory of the one in which this
# script is located.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Disable pip's version check and root user warning
export PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_ROOT_USER_ACTION=ignore

if ! command -v ansible >/dev/null 2>&1; then
    pip3_install "ansible-core==${_version_ansible_core}"
    ensure_py3_bin ansible
    ensure_py3_bin ansible-playbook
fi

ansible_version=""
IFS=" " read -ra ansible_version <<< "$(ansible --version)"
if [[ "${_version_ansible_core}" != $(echo -e "${_version_ansible_core}\n${ansible_version[2]}" | sort -s -t. -k 1,1 -k 2,2n -k 3,3n | head -n1) && "${ansible_version[2]}" != "devel" ]]; then
  cat <<EOF
Detected ansible version: ${ansible_version[*]}.
Image builder requires ${_version_ansible_core} or greater.
Please install ${_version_ansible_core} or later.
EOF
  exit 2
fi

echo ${ansible_version[*]}

ansible-galaxy collection install \
  community.general \
  ansible.posix \
  'ansible.windows:>=1.7.0' \
  community.windows
