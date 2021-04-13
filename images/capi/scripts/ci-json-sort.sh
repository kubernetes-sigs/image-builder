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

cleanup() {
    returnCode="$?"
    exit "${returnCode}"
}

trap cleanup EXIT

json_files=$(find . -type f -name "*.json" | sort -u)
for f in ${json_files}
do
  if ! diff <(jq -S . ${f}) ${f} >> /dev/null; then
    echo "json files are not sorted!! Please sort them with \"make json-sort\" in \"images/capi\" before commit"
    echo "Unsorted file: ${f}"
    exit 1
  fi
done
