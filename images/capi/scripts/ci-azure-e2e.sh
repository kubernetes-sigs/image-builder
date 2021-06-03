#!/bin/bash

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

###############################################################################

# This script is executed by presubmit `pull-cluster-api-provider-azure-e2e`
# To run locally, set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

CAPI_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
cd "${CAPI_ROOT}" || exit 1

# shellcheck source=parse-prow-creds.sh
source "packer/azure/scripts/parse-prow-creds.sh"

# Verify the required Environment Variables are present.
: "${AZURE_SUBSCRIPTION_ID:?Environment variable empty or not defined.}"
: "${AZURE_TENANT_ID:?Environment variable empty or not defined.}"
: "${AZURE_CLIENT_ID:?Environment variable empty or not defined.}"
: "${AZURE_CLIENT_SECRET:?Environment variable empty or not defined.}"

get_random_region() {
    local REGIONS=("eastus" "eastus2" "southcentralus" "westus2" "westeurope")
    echo "${REGIONS[${RANDOM} % ${#REGIONS[@]}]}"
}

export PATH=${PWD}/.local/bin:$PATH
export PATH=${PYTHON_BIN_DIR:-"/root/.local/bin"}:$PATH

export AZURE_LOCATION="${AZURE_LOCATION:-$(get_random_region)}"
export RESOURCE_GROUP_NAME="image-builder-e2e-$(head /dev/urandom | LC_ALL=C tr -dc a-z0-9 | head -c 6 ; echo '')"

# timestamp is in RFC-3339 format to match kubetest
export TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
export JOB_NAME="${JOB_NAME:-"image-builder-e2e"}"
export TAGS="creationTimestamp=${TIMESTAMP} jobName=${JOB_NAME}"

cleanup() {
    az group delete -n ${RESOURCE_GROUP_NAME} --yes --no-wait || true
}

trap cleanup EXIT

make deps-azure

# Pre-pulling windows images takes 10-20 mins
# Disable them for CI runs so don't run into timeouts
export PACKER_VAR_FILES="packer/azure/scripts/disable-windows-prepull.json scripts/ci-disable-goss-inspect.json"

if [[ "${AZURE_BUILD_FORMAT:-vhd}" == "sig" ]]; then
    make -j build-azure-sigs
else
    make -j build-azure-vhds
fi
