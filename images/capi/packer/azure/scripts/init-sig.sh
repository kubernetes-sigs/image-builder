#!/bin/bash

[[ -n ${DEBUG:-} ]] && set -o xtrace

tracestate="$(shopt -po xtrace)"
set +o xtrace
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID} >/dev/null 2>&1 
az account set -s ${AZURE_SUBSCRIPTION_ID} >/dev/null 2>&1 
eval "$tracestate"

export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-images}"
export AZURE_LOCATION="${AZURE_LOCATION:-southcentralus}"
az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION} --tags ${TAGS:-}
CREATE_TIME="$(date +%s)"
RANDOM_SUFFIX="$(head /dev/urandom | LC_ALL=C tr -dc a-z | head -c 4 ; echo '')"
export GALLERY_NAME="${GALLERY_NAME:-ClusterAPI${CREATE_TIME}${RANDOM_SUFFIX}}"
az sig create --resource-group ${RESOURCE_GROUP_NAME} --gallery-name ${GALLERY_NAME}
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-ubuntu-1804 \
   --publisher capz \
   --offer capz-demo \
   --sku 18.04-LTS \
   --os-type Linux
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-ubuntu-2004 \
   --publisher capz \
   --offer capz-demo \
   --sku 20_04-lts \
   --os-type Linux
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-centos-7.7 \
   --publisher capz \
   --offer capz-demo \
   --sku centos-7.7 \
   --os-type Linux
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-windows-2019-docker-ee \
   --publisher capz \
   --offer capz-demo \
   --sku win-2019-docker-ee \
   --os-type Windows
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-windows-2019-containerd \
   --publisher capz \
   --offer capz-demo \
   --sku win-2019-containerd \
   --os-type Windows
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-flatcar-${FLATCAR_CHANNEL}-${FLATCAR_VERSION} \
   --publisher capz \
   --offer capz-demo \
   --sku flatcar-${FLATCAR_CHANNEL}-${FLATCAR_VERSION} \
   --os-type Linux
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-ubuntu-1804-gen2 \
   --publisher capz \
   --offer capz-demo \
   --sku 18.04-lts-gen2 \
   --hyper-v-generation V2 \
   --os-type Linux
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-ubuntu-2004-gen2 \
   --publisher capz \
   --offer capz-demo \
   --sku 20_04-lts-gen2 \
   --hyper-v-generation V2 \
   --os-type Linux
az sig image-definition create \
   --resource-group ${RESOURCE_GROUP_NAME} \
   --gallery-name ${GALLERY_NAME} \
   --gallery-image-definition capi-centos-7.7-gen2 \
   --publisher capz \
   --offer capz-demo \
   --sku centos-7.7-gen2 \
   --hyper-v-generation V2 \
   --os-type Linux
