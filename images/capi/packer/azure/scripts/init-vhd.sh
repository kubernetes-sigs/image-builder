#!/bin/bash

tracestate="$(shopt -po xtrace)"
set +o xtrace
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID} >/dev/null 2>&1 
az account set -s ${AZURE_SUBSCRIPTION_ID} >/dev/null 2>&1 
eval "$tracestate"

export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-images}"
export AZURE_LOCATION="${AZURE_LOCATION:-southcentralus}"
az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION} --tags ${TAGS}
CREATE_TIME="$(date +%s)"
export STORAGE_ACCOUNT_NAME="capi${CREATE_TIME}"
az storage account create -n ${STORAGE_ACCOUNT_NAME} -g ${RESOURCE_GROUP_NAME}
