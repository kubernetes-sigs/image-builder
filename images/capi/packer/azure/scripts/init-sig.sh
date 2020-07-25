#!/bin/bash

az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
az account set -s ${AZURE_SUBSCRIPTION_ID}
export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-images}"
export AZURE_LOCATION="${AZURE_LOCATION:-southcentralus}"
az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION}
echo "resource group name: ${RESOURCE_GROUP_NAME}"
export GALLERY_NAME="${GALLERY_NAME:-ClusterAPI}"
az sig create --resource-group ${RESOURCE_GROUP_NAME} --gallery-name ${GALLERY_NAME}
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ClusterAPI \
   --gallery-image-definition capi-ubuntu-1804 \
   --publisher capz \
   --offer capz-demo \
   --sku 18.04-LTS \
   --os-type Linux