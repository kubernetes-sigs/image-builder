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

# Dynamically gets all targets and filters out the following:
# - Any RHEL targets (because of subscription requirements)
VHD_CI_TARGETS=( $(make build-azure-vhds --recon -d | grep "Must remake" | \
  grep -v build-azure-vhds | grep -v deps- | \
  grep -v gen2 | grep -v cvm | \
  grep -E -v 'rhel' | \
  grep -E -o 'build-azure-vhd-[a-zA-Z0-9\-]+' | \
  sed -E 's/build-azure-vhd-([0-9a-z\-]*)/\1/' ) )
SIG_CI_TARGETS=( $(make build-azure-sigs --recon -d | grep "Must remake" | \
  grep -v build-azure-sigs | grep -v deps- | \
  grep -v cvm | \
  grep -E -v 'rhel' | \
  grep -E -o 'build-azure-sig-[a-zA-Z0-9\-]+' | \
  sed -E 's/build-azure-sig-([0-9a-z\-]*)/\1/' ) )
SIG_CVM_CI_TARGETS=( $(make build-azure-sigs --recon -d | grep "Must remake" | \
  grep cvm | \
  grep -E -v 'rhel' | \
  grep -E -o 'build-azure-sig-[a-zA-Z0-9\-]+' | \
  sed -E 's/build-azure-sig-([0-9a-z\-]*)/\1/' ) )

# shellcheck source=parse-prow-creds.sh
source "packer/azure/scripts/parse-prow-creds.sh"

# Verify the required Environment Variables are present.
: "${AZURE_SUBSCRIPTION_ID:?Environment variable empty or not defined.}"
: "${AZURE_TENANT_ID:?Environment variable empty or not defined.}"
: "${AZURE_CLIENT_ID:?Environment variable empty or not defined.}"
set +o nounset
if [ -z "${AZURE_FEDERATED_TOKEN_FILE}" ] && [ -z "${AZURE_CLIENT_SECRET}" ]; then
  echo "Either AZURE_FEDERATED_TOKEN_FILE or AZURE_CLIENT_SECRET must be set."
  exit 1
fi
set -o nounset

get_random_region() {
    local REGIONS=("australiaeast" "canadacentral" "eastus" "eastus2" "northcentralus" "northeurope" "uksouth" "westeurope" "westus2")
    echo "${REGIONS[${RANDOM} % ${#REGIONS[@]}]}"
}

export VALID_CVM_LOCATIONS=("eastus" "northeurope" "westeurope" "westus")
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

login() {
  if [[ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]]; then
    az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "$(cat "${AZURE_FEDERATED_TOKEN_FILE}")"
    export USE_AZURE_CLI_AUTH=True  # Packer will use this existing login for its authentication
  else
    az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" -p "${AZURE_CLIENT_SECRET}"
  fi
}

# Latest Flatcar version is often available on Azure with a delay, so resolve ourselves
get_flatcar_version() {
    az vm image show --urn kinvolk:flatcar-container-linux-free:stable:latest --query 'name' -o tsv
}
login
export FLATCAR_VERSION="$(get_flatcar_version)"

# Pre-pulling windows images takes 10-20 mins
# Disable them for CI runs so don't run into timeouts
export PACKER_VAR_FILES="packer/azure/scripts/disable-windows-prepull.json scripts/ci-disable-goss-inspect.json"

declare -A PIDS
if [[ "${AZURE_BUILD_FORMAT:-vhd}" == "sig" ]]; then
    for target in ${SIG_CI_TARGETS[@]};
    do
        login
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
        login
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
