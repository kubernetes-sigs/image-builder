#!/bin/bash

set -e

az cloud set --name ${AZURE_ENVIRONMENT:-AzurePublicCloud}
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
az account set -s ${AZURE_SUBSCRIPTION_ID}
export RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-cluster-api-images}
export AZURE_LOCATION="${AZURE_LOCATION:-southcentralus}"
az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION}
echo "resource group name: ${RESOURCE_GROUP_NAME}"
CREATE_TIME="$(date +%s)"
export STORAGE_ACCOUNT_NAME="photon3"
