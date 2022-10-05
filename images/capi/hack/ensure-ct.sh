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

_version="v0.9.3"

# Change directories to the parent directory of the one in which this
# script is located.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

source hack/utils.sh

if command -v ct >/dev/null 2>&1; then exit 0; fi

mkdir -p .local/bin && cd .local/bin

if [[ ${HOSTOS} == "linux" ]]; then
  _binfile="ct-${_version}-x86_64-unknown-linux-gnu"
elif [[ ${HOSTOS} == "darwin" ]]; then
  _binfile="ct-${_version}-x86_64-apple-darwin"
fi
_bin_url="https://github.com/flatcar/container-linux-config-transpiler/releases/download/${_version}/${_binfile}"
curl -SsL "${_bin_url}" -o ct
chmod 0755 ct
echo "'ct' has been installed to $(pwd), make sure this directory is in your \$PATH"
