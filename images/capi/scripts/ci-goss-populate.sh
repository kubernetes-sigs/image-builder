#!/bin/bash

# Copyright 2021 The Kubernetes Authors.
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

###############################################################################

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

CAPI_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
cd "${CAPI_ROOT}" || exit 1

source hack/utils.sh
ensure_py3

_version="v0.3.16"
_bin_url="https://github.com/aelsabbahy/goss/releases/download/${_version}/goss-linux-amd64"

if ! command -v goss >/dev/null 2>&1; then
  if [[ ${HOSTOS} == "linux" ]]; then
    curl -SsL "${_bin_url}" -o goss
    chmod +x goss
    mkdir -p "${PWD}/.local/bin"
    mv goss "${PWD}/.local/bin"
    export PATH=${PWD}/.local/bin:$PATH
  fi
fi

export GOSS_USE_ALPHA=1
hack/generate-goss-specs.py
