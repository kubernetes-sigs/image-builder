#!/bin/bash

# Copyright 2019 The Kubernetes Authors.
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

[[ -n ${DEBUG:-} ]] && set -o xtrace

tracestate="$(shopt -po xtrace)"
set +o xtrace
if [[ "${USE_AZURE_CLI_AUTH:-}" == "True" ]]; then
  : # Assume we did "az login" before running this script
elif [[ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]]; then
  az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "$(cat "${AZURE_FEDERATED_TOKEN_FILE}")" >/dev/null 2>&1
else
  az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" -p "${AZURE_CLIENT_SECRET}" >/dev/null 2>&1
fi
az account set -s ${AZURE_SUBSCRIPTION_ID} >/dev/null 2>&1
eval "$tracestate"

export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-gallery}"
export AZURE_LOCATION="${AZURE_LOCATION:-northcentralus}"
if ! az group show -n ${RESOURCE_GROUP_NAME} -o none 2>/dev/null; then
  az group create -n ${RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION} --tags ${TAGS:-}
fi
CREATE_TIME="$(date +%s)"
RANDOM_SUFFIX="$(head /dev/urandom | LC_ALL=C tr -dc a-z | head -c 4 ; echo '')"
export GALLERY_NAME="${GALLERY_NAME:-ClusterAPI${CREATE_TIME}${RANDOM_SUFFIX}}"

# Hack to set only build_resource_group_name or location, a better solution is welcome
# https://developer.hashicorp.com/packer/plugins/builders/azure/arm#build_resource_group_name
PACKER_FILE_PATH=packer/azure/
TMP_PACKER_FILE=$PACKER_FILE_PATH"packer.json.tmp"
PACKER_FILE=$PACKER_FILE_PATH"packer.json"
if [ ${BUILD_RESOURCE_GROUP_NAME} ]; then
    if ! az group show -n ${BUILD_RESOURCE_GROUP_NAME} -o none 2>/dev/null; then
        az group create -n ${BUILD_RESOURCE_GROUP_NAME} -l ${AZURE_LOCATION} --tags ${TAGS:-}
    fi
    jq '(.builders | map(if .name | contains("sig") then del(.location) + {"build_resource_group_name": "{{user `build_resource_group_name`}}"} else . end)) as $updated | .builders = $updated' $PACKER_FILE  > $TMP_PACKER_FILE
    mv $TMP_PACKER_FILE $PACKER_FILE
fi

packer validate -syntax-only $PACKER_FILE || exit 1

az sig create --resource-group ${RESOURCE_GROUP_NAME} --gallery-name ${GALLERY_NAME}

SECURITY_TYPE_CVM_SUPPORTED_FEATURE="SecurityType=ConfidentialVmSupported"

SIG_TARGET=$1

# Accept Azure VM image terms if available and required
accept_image_terms() {
  # SIG_TARGET is expected to be a global variable
  if [[ -z "$SIG_TARGET" ]]; then
    echo "Error: SIG_TARGET is not set. Exiting."
    exit 1
  fi
  # AZURE_LOCATION is expected to be a global variable
  if [[ -z "$AZURE_LOCATION" ]]; then
    echo "Error: AZURE_LOCATION is not set. Exiting."
    exit 1
  fi

  # Resolve the JSON file path and extract necessary fields
  target_json="$(realpath "packer/azure/${SIG_TARGET}.json")"
  distribution=$(jq -r '.distribution' "$target_json")
  distribution_version=$(jq -r '.distribution_version' "$target_json")

  # Return early if not a Windows distribution
  if [[ "$distribution" != "windows" ]]; then
    return
  fi

  # Extract purchase plan details
  plan_publisher=$(jq -r '.plan_image_publisher' "$target_json")
  plan_offer=$(jq -r '.plan_image_offer' "$target_json")
  plan_name=$(jq -r '.plan_image_sku' "$target_json")
  plan_version=${PLAN_VERSION:-"latest"}

  # Proceed only if all plan details are valid
  if [[ "$plan_publisher" == "null" || "$plan_offer" == "null" || "$plan_name" == "null" ]]; then
    echo "Purchase plan details are missing. Skipping terms acceptance."
    return
  fi

  # Populate the global plan_args variable
  PLAN_ARGS=(
    --plan-name "${plan_name}"
    --plan-product "${plan_offer}"
    --plan-publisher "${plan_publisher}"
  )

  plan_urn="${plan_publisher}:${plan_offer}:${plan_name}:${plan_version}"

  # Check if the image has terms to accept
  if [[ "$(az vm image show --location "$AZURE_LOCATION" --urn "${plan_urn}" -o json | jq -r '.plan')" == "null" ]]; then
    echo "Image '${plan_urn}' has no terms to accept."
    return
  fi

  echo "Plan info: ${plan_urn}"

  # Check acceptance status and accept terms if not already accepted
  if [[ "$(az vm image terms show --urn "$plan_urn" -o json | jq -r '.accepted')" == "true" ]]; then
    echo "Terms for image URN: ${plan_urn} are already accepted."
    return
  fi

  echo "Accepting terms for image URN: ${plan_urn}"
  az vm image terms accept --urn "$plan_urn"
}

PLAN_ARGS=()
accept_image_terms

# Create a shared image gallery image definition if it does not exist
create_image_definition() {
  if ! az sig image-definition show --gallery-name ${GALLERY_NAME} --gallery-image-definition ${SIG_IMAGE_DEFINITION:-capi-${SIG_SKU:-$1}} --resource-group ${RESOURCE_GROUP_NAME} -o none 2>/dev/null; then
    az sig image-definition create \
      --resource-group ${RESOURCE_GROUP_NAME} \
      --gallery-name ${GALLERY_NAME} \
      --gallery-image-definition ${SIG_IMAGE_DEFINITION:-capi-${SIG_SKU:-$1}} \
      --publisher ${SIG_PUBLISHER:-capz} \
      --offer ${SIG_OFFER:-capz-demo} \
      --sku ${SIG_SKU:-$2} \
      --hyper-v-generation ${3} \
      --os-type ${4} \
      --features ${5:-''} \
      "${plan_args[@]}" # TODO: Delete this line after the image is GA
  fi
}

case ${SIG_TARGET} in
  ubuntu-2204)
    create_image_definition ${SIG_TARGET} "22_04-lts" "V1" "Linux"
  ;;
  ubuntu-2404)
    create_image_definition ${SIG_TARGET} "24_04-lts" "V1" "Linux"
  ;;
  azurelinux-3)
    create_image_definition ${SIG_TARGET} "azurelinux-3" "V1" "Linux"
  ;;
  rhel-8)
    create_image_definition "rhel-8" "rhel-8" "V1" "Linux"
  ;;
  windows-2019-containerd)
    create_image_definition ${SIG_TARGET} "win-2019-containerd" "V1" "Windows"
  ;;
  windows-2022-containerd)
    create_image_definition ${SIG_TARGET} "win-2022-containerd" "V1" "Windows"
  ;;
  windows-2025-containerd)
    create_image_definition ${SIG_TARGET} "win-2025-containerd" "V1" "Windows"
  ;;
  windows-annual-containerd)
    create_image_definition ${SIG_TARGET} "win-annual-containerd" "V1" "Windows"
  ;;
  windows-2019-containerd-cvm)
    SKU="windows-2019-cvm-containerd"
    create_image_definition ${SKU} ${SKU} "V2" "Windows" ${SECURITY_TYPE_CVM_SUPPORTED_FEATURE}
  ;;
  windows-2022-containerd-cvm)
    SKU="windows-2022-cvm-containerd"
    create_image_definition ${SKU} ${SKU} "V2" "Windows" ${SECURITY_TYPE_CVM_SUPPORTED_FEATURE}
  ;;
  flatcar)
    SKU="flatcar-${FLATCAR_CHANNEL}-${FLATCAR_VERSION}"
    create_image_definition ${SKU} ${SKU} "V1" "Linux"
  ;;
  ubuntu-2204-gen2)
    create_image_definition ${SIG_TARGET} "22_04-lts-gen2" "V2" "Linux"
  ;;
  ubuntu-2204-cvm)
    create_image_definition ${SIG_TARGET} "22_04-lts-cvm" "V2" "Linux" ${SECURITY_TYPE_CVM_SUPPORTED_FEATURE}
  ;;
  ubuntu-2404-gen2)
    create_image_definition ${SIG_TARGET} "24_04-lts-gen2" "V2" "Linux"
  ;;
  ubuntu-2404-cvm)
    create_image_definition ${SIG_TARGET} "24_04-lts-cvm" "V2" "Linux" ${SECURITY_TYPE_CVM_SUPPORTED_FEATURE}
  ;;
  azurelinux-3-gen2)
    create_image_definition ${SIG_TARGET} "azurelinux-3-gen2" "V2" "Linux"
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
