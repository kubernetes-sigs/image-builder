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

_version="0.4.2"

if [[ ${HOSTOS} == "darwin" ]]; then
    echo "IMPORTANT: Winrm connection plugin for Ansible on MacOS causes connection issues."
    echo "See https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html#what-is-winrm for more details."
    echo "To fix the issue provide the enviroment variable 'no_proxy=*'" 
    echo "Example call to build Windows images on MacOS: 'no_proxy=* make build-<target>'"
fi

# Change directories to the parent directory of the one in which this
# script is located.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if pip3 show pywinrm >/dev/null 2>&1; then exit 0; fi

ensure_py3
pip3 install --user "pywinrm==${_version}"
if ! pip3 show pywinrm ; then exit 1; fi
