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

_version="2.11.5"

# Change directories to the parent directory of the one in which this
# script is located.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v ansible >/dev/null 2>&1; then
    ensure_py3
    pip3 install --user "ansible-core==${_version}"
    ensure_py3_bin ansible
    ensure_py3_bin ansible-playbook
fi

ansible-galaxy collection install \
  community.general \
  ansible.posix \
  'ansible.windows:>=1.7.0' \
  community.windows
