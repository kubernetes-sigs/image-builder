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

# Change directories to the parent directory of the one in which this
# script is located.
CAPI_ROOT=$(dirname "${BASH_SOURCE[0]}")/../../..
cd "${CAPI_ROOT}" || exit 1

source hack/utils.sh

if command -v kustomize >/dev/null 2>&1; then exit 0; fi

mkdir -p .local/bin && cd .local/bin

# There is no darwin/arm64 version so we need to default HOSTARCH to amd64 if on an M1/M2 Mac
HOSTARCH=$(hostarch_without_darwin_arm64)

KUSTOMIZE_VERSION=4.5.2
_binfile="kustomize-v${KUSTOMIZE_VERSION}.tar.gz"

echo "installing kustomize"
curl -sLo "${_binfile}" "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_${HOSTOS}_${HOSTARCH}.tar.gz"
tar -zvxf "${_binfile}" -C "./"
chmod +x "./kustomize"
rm "${_binfile}"
echo "'kustomize' has been installed to $(pwd), make sure this directory is in your \$PATH"
