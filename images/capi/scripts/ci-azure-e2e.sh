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

export ARTIFACTS="${ARTIFACTS:-${PWD}/_artifacts}"
mkdir -p "${ARTIFACTS}/azure-sigs" "${ARTIFACTS}/azure-vhds"

# Get list of Azure target names from common file
source azure_targets.sh

# Convert single line entries into arrays
IFS=' ' read -r -a VHD_CI_TARGETS <<< "${VHD_CI_TARGETS}"
IFS=' ' read -r -a SIG_CI_TARGETS <<< "${SIG_CI_TARGETS}"
IFS=' ' read -r -a SIG_GEN2_CI_TARGETS <<< "${SIG_GEN2_CI_TARGETS}"
IFS=' ' read -r -a SIG_CVM_CI_TARGETS <<< "${SIG_CVM_CI_TARGETS}"

# Append the "gen2" targets to the original SIG list
for element in "${SIG_GEN2_CI_TARGETS[@]}"
do
    SIG_CI_TARGETS+=("${element}-gen2")
done

# Append "-cvm" suffix to SIG CVM targets
SIG_CVM_CI_TARGETS=("${SIG_CVM_CI_TARGETS[@]/%/-cvm}")

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

export VALID_CVM_LOCATIONS=("eastus" "westus" "northeurope" "westeurope")
get_random_cvm_region() {
    echo "${VALID_CVM_LOCATIONS[${RANDOM} % ${#VALID_CVM_LOCATIONS[@]}]}"
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

# Latest Flatcar version is often available on Azure with a delay, so resolve ourselves
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
get_flatcar_version() {
    az vm image show --urn kinvolk:flatcar-container-linux-free:stable:latest --query 'name' -o tsv
}
export FLATCAR_VERSION="$(get_flatcar_version)"

# Pre-pulling windows images takes 10-20 mins
# Disable them for CI runs so don't run into timeouts
export PACKER_VAR_FILES="packer/azure/scripts/disable-windows-prepull.json scripts/ci-disable-goss-inspect.json"

declare -A PIDS
if [[ "${AZURE_BUILD_FORMAT:-vhd}" == "sig" ]]; then
    for target in ${SIG_CI_TARGETS[@]};
    do
        make build-azure-sig-${target} > ${ARTIFACTS}/azure-sigs/${target}.log 2>&1 &
        PIDS["sig-${target}"]=$!
    done

    SELECTED_LOCATION="${AZURE_LOCATION}"
    if [[ ! " ${VALID_CVM_LOCATIONS[*]} " =~ " ${SELECTED_LOCATION} " ]]; then
        SELECTED_LOCATION="$(get_random_cvm_region)"
        echo "AZURE_LOCATION=${AZURE_LOCATION} is invalid for Confidential VM targets. Valid CVM locations: ${VALID_CVM_LOCATIONS[*]}."
        echo "Selected location is ${SELECTED_LOCATION}."
    fi

    for target in ${SIG_CVM_CI_TARGETS[@]};
    do
        AZURE_LOCATION="${SELECTED_LOCATION}" make build-azure-sig-${target} > ${ARTIFACTS}/azure-sigs/${target}.log 2>&1 &
        PIDS["sig-${target}"]=$!
    done
else
    for target in ${VHD_CI_TARGETS[@]};
    do
        make build-azure-vhd-${target} > ${ARTIFACTS}/azure-vhds/${target}.log 2>&1 &
        PIDS["vhd-${target}"]=$!
    done
fi

# need to unset errexit so that failed child tasks don't cause script to exit
set +o errexit
exit_err=false
for target in "${!PIDS[@]}"; do
  wait ${PIDS[$target]}
  if [[ $? -ne 0 ]]; then
    exit_err=true
    echo "${target}: FAILED. See logs in the artifacts folder."
  else
    echo "${target}: SUCCESS"
  fi
done

if [[ "${exit_err}" = true ]]; then
  exit 1
fi
