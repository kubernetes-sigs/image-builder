#!/bin/bash

[[ -n ${DEBUG:-} ]] && set -o xtrace

echo "Sign into Azure"
tracestate="$(shopt -po xtrace)"
set +o xtrace
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID} >/dev/null 2>&1
az account set -s ${AZURE_SUBSCRIPTION_ID} >/dev/null 2>&1
eval "$tracestate"

echo "Create storage account"
export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-images}"
export AZURE_LOCATION="${AZURE_LOCATION:-southcentralus}"
az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION} --tags ${TAGS:-}
CREATE_TIME="$(date +%s)"
RANDOM_SUFFIX="$(head /dev/urandom | LC_ALL=C tr -dc a-z | head -c 4 ; echo '')"
export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-capi${CREATE_TIME}${RANDOM_SUFFIX}}"
az storage account check-name --name ${STORAGE_ACCOUNT_NAME}
az storage account create -n ${STORAGE_ACCOUNT_NAME} -g ${RESOURCE_GROUP_NAME}

echo "done"