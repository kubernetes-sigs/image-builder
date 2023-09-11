#!/usr/bin/env bash

# Copyright 2023 The Kubernetes Authors.
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

# Python 3.9 or later is required, specifically for Ansible 2.14 or later.
minimum_python_version=3.9.0

# Ensure that Python exists and is a viable version.
verify_python_version() {
  if [[ -z "$(command -v python3)" ]]; then
    cat <<EOF
Can't find 'python3' in PATH, please fix and retry.
See https://www.python.org/downloads/ for installation instructions.
EOF
    return 2
  fi

  local python_version
  IFS=" " read -ra python_version <<< "$(python3 --version)"
  if [[ "${minimum_python_version}" != $(echo -e "${minimum_python_version}\n${python_version[1]}" | sort -s -t. -k 1,1 -k 2,2n -k 3,3n | head -n1) && "${python_version[1]}" != "devel" ]]; then
    cat <<EOF
Detected python version: ${python_version[*]}.
Ansible requires ${minimum_python_version} or greater.
Please install ${minimum_python_version} or later.
EOF
    return 2
  fi
}

echo "Checking if python is available"
verify_python_version

python3 --version
