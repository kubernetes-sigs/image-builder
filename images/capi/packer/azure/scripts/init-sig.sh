#!/bin/bash

[[ -n ${DEBUG:-} ]] && set -o xtrace

tracestate="$(shopt -po xtrace)"
set +o xtrace
az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID} >/dev/null 2>&1
az account set -s ${AZURE_SUBSCRIPTION_ID} >/dev/null 2>&1
eval "$tracestate"

export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-images}"
export AZURE_LOCATION="${AZURE_LOCATION:-southcentralus}"
if ! az group show -n ${RESOURCE_GROUP_NAME} -o none 2>/dev/null; then
  az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION} --tags ${TAGS:-}
fi
CREATE_TIME="$(date +%s)"
RANDOM_SUFFIX="$(head /dev/urandom | LC_ALL=C tr -dc a-z | head -c 4 ; echo '')"
export GALLERY_NAME="${GALLERY_NAME:-ClusterAPI${CREATE_TIME}${RANDOM_SUFFIX}}"
az sig create --resource-group ${RESOURCE_GROUP_NAME} --gallery-name ${GALLERY_NAME}

create_image_definition() {
  az sig image-definition create \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --gallery-name ${GALLERY_NAME} \
    --gallery-image-definition capi-${1} \
    --publisher capz \
    --offer capz-demo \
    --sku ${2} \
    --hyper-v-generation ${3} \
    --os-type ${4}
}

SIG_TARGET=$1

case ${SIG_TARGET} in
  ubuntu-1804)
    create_image_definition ${SIG_TARGET} "18.04-LTS" "V1" "Linux"
  ;;
  ubuntu-2004)
    create_image_definition ${SIG_TARGET} "20_04-lts" "V1" "Linux"
  ;;
  ubuntu-2204)
    create_image_definition ${SIG_TARGET} "22_04-lts" "V1" "Linux"
  ;;
  centos-7)
    create_image_definition "centos-7.7" "centos-7.7" "V1" "Linux"
  ;;
  windows-2019)
    create_image_definition "windows-2019-docker-ee" "win-2019-docker-ee" "V1" "Windows"
  ;;
  windows-2019-containerd)
    create_image_definition ${SIG_TARGET} "win-2019-containerd" "V1" "Windows"
  ;;
  windows-2022-containerd)
    create_image_definition ${SIG_TARGET} "win-2022-containerd" "V1" "Windows"
  ;;
  flatcar)
    SKU="flatcar-${FLATCAR_CHANNEL}-${FLATCAR_VERSION}"
    create_image_definition ${SKU} ${SKU} "V1" "Linux"
  ;;
  ubuntu-1804-gen2)
    create_image_definition ${SIG_TARGET} "18.04-lts-gen2" "V2" "Linux"
  ;;
  ubuntu-2004-gen2)
    create_image_definition ${SIG_TARGET} "20_04-lts-gen2" "V2" "Linux"
  ;;
  ubuntu-2204-gen2)
    create_image_definition ${SIG_TARGET} "22_04-lts-gen2" "V2" "Linux"
  ;;
  centos-7-gen2)
    create_image_definition "centos-7.7-gen2" "centos-7.7-gen2" "V2" "Linux"
  ;;
  flatcar-gen2)
    SKU="flatcar-${FLATCAR_CHANNEL}-${FLATCAR_VERSION}-gen2"
    create_image_definition "${SKU}" "${SKU}" "V2" "Linux"
  ;;
  *)
    >&2 echo "Unsupported SIG target: '${SIG_TARGET}'"
    exit 1
  ;;
esac
