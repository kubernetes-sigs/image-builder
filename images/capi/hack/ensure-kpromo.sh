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

MINIMUM_KPROMO_VERSION="v3.6.0"

# Ensure the kpromo tool exists and is a viable version.
verify_kpromo_version() {
  if [[ -z "$(command -v kpromo)" ]]; then
    if [[ "${INSTALL_KPROMO:-"true"}" == "true" ]]; then
      go install sigs.k8s.io/promo-tools/v3/cmd/kpromo@${MINIMUM_KPROMO_VERSION}
      export PATH=$(go env GOPATH)/bin:$PATH
    else
      cat <<EOF
Can't find 'kpromo' in PATH, please fix and retry.
See https://github.com/kubernetes-sigs/promo-tools#installation for installation instructions.
EOF
      return 2
    fi
  fi

  local kpromo_version
  kpromo_version=$(kpromo version --json 2>&1 | jq -r .gitVersion)
  if [[ "${MINIMUM_KPROMO_VERSION}" != $(echo -e "${MINIMUM_KPROMO_VERSION}\n${kpromo_version}" | sort -s -t. -k 1,1 -k 2,2n -k 3,3n | head -n1) && "${kpromo_version}" != "devel" ]]; then
    cat <<EOF
Detected kpromo version: ${kpromo_version[*]}.
Image builder releases require ${MINIMUM_KPROMO_VERSION} or greater.
Please install kpromo ${MINIMUM_KPROMO_VERSION} or later.
See https://github.com/kubernetes-sigs/promo-tools#installation for
instructions, or remove the kpromo binary and re-run this script.
EOF
    return 2
  fi
}

echo "Checking if kpromo is available"
verify_kpromo_version

kpromo version
