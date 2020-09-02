#!/bin/bash

tracestate="$(shopt -po xtrace)"
set +o xtrace
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID} >/dev/null 2>&1 
az account set -s ${AZURE_SUBSCRIPTION_ID} >/dev/null 2>&1 
eval "$tracestate"

export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-images}"
export AZURE_LOCATION="${AZURE_LOCATION:-southcentralus}"
az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION}
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
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ClusterAPI \
   --gallery-image-definition capi-ubuntu-2004 \
   --publisher capz \
   --offer capz-demo \
   --sku 20_04-lts \
   --os-type Linux