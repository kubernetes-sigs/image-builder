#!/bin/bash

[[ -n ${DEBUG:-} ]] && set -o xtrace

echo "Sign into Azure"
tracestate="$(shopt -po xtrace)"
set +o xtrace

if [[ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]]; then
  az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "$(cat "${AZURE_FEDERATED_TOKEN_FILE}")" > /dev/null 2>&1
  export AZURE_STORAGE_AUTH_MODE="login"   # Use auth mode "login" in az storage commands.
else
  az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" -p ${AZURE_CLIENT_SECRET} >/dev/null 2>&1
fi
az account set -s ${AZURE_SUBSCRIPTION_ID} >/dev/null 2>&1
eval "$tracestate"

echo "Create storage account"
export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-images}"
export AZURE_LOCATION="${AZURE_LOCATION:-northcentralus}"
if ! az group show -n ${RESOURCE_GROUP_NAME} -o none 2>/dev/null; then
  az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION} --tags ${TAGS:-}
fi
CREATE_TIME="$(date +%s)"
RANDOM_SUFFIX="$(head /dev/urandom | LC_ALL=C tr -dc a-z | head -c 4 ; echo '')"
get_random_region() {
  local REGIONS=("canadacentral" "eastus" "eastus2" "northeurope" "uksouth" "westeurope" "westus2" "westus3")
  echo "${REGIONS[${RANDOM} % ${#REGIONS[@]}]}"
}
RANDOMIZE_STORAGE_ACCOUNT="${RANDOMIZE_STORAGE_ACCOUNT:-"false"}"
if [ "$RANDOMIZE_STORAGE_ACCOUNT" == "true" ]; then
  export AZURE_LOCATION="$(get_random_region)"
fi
export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-capi${CREATE_TIME}${RANDOM_SUFFIX}}"
az storage account check-name --name ${STORAGE_ACCOUNT_NAME}
az storage account create -n ${STORAGE_ACCOUNT_NAME} -g ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION} --allow-blob-public-access false

echo "done"
