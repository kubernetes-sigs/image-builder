#!/bin/bash

[[ -n ${DEBUG:-} ]] && set -o xtrace

tracestate="$(shopt -po xtrace)"
set +o xtrace
if [[ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]]; then
  az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "$(cat "${AZURE_FEDERATED_TOKEN_FILE}")" >/dev/null 2>&1
else
  az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" -p "${AZURE_CLIENT_SECRET}" >/dev/null 2>&1
fi
az account set -s ${AZURE_SUBSCRIPTION_ID} >/dev/null 2>&1
eval "$tracestate"

export RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-cluster-api-images}"
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


#################################################################################
##### TODO: [SEPTEMBER 2024] Remove purchase plan info when the image is GA #####
# Creating Azure VMs from a Marketplace Image requires a Purchase Plan
# https://learn.microsoft.com/en-us/azure/virtual-machines/marketplace-images
# HACK: Extract purchase plan info from the target json. We want to avoid changing the Prow jobs YAML files to add these
# values as environment variables.
TARGET_JSON="$(realpath packer/azure/$SIG_TARGET.json)"
DISTRIBUTION=$(jq -r '.distribution' "$TARGET_JSON")
DISTRIBUTION_VERSION=$(jq -r '.distribution_version' "$TARGET_JSON")

plan_args=()
if [[ "$DISTRIBUTION" == "windows" && "$DISTRIBUTION_VERSION" == "2025" ]]; then
  PLAN_PUBLISHER=$(jq -r '.plan_image_publisher' "$TARGET_JSON")
  PLAN_OFFER=$(jq -r '.plan_image_offer' "$TARGET_JSON")
  PLAN_NAME=$(jq -r '.plan_image_sku' "$TARGET_JSON")
  PLAN_VERSION=${PLAN_VERSION:-"latest"}

  plan_args=(
    --plan-name ${PLAN_NAME}
    --plan-product ${PLAN_OFFER}
    --plan-publisher ${PLAN_PUBLISHER}
  )

  # Proceed only if all plan details are available
  # WHY? Build fails with: "You have not accepted the legal terms on this subscription"
  if [[ "$PLAN_PUBLISHER" != "null" && "$PLAN_OFFER" != "null" && "$PLAN_NAME" != "null" ]]; then
    PLAN_URN="${PLAN_PUBLISHER}:${PLAN_OFFER}:${PLAN_NAME}:$(echo $PLAN_VERSION)"
    echo "Plan info: ${PLAN_URN}"

    # Retrieve the terms and check acceptance status
    if [[ "$(az vm image terms show --urn "$PLAN_URN" | jq -r '.accepted')" != "true" ]]; then
      echo "Accepting terms for image URN: ${PLAN_URN}"
      az vm image terms accept --urn "$PLAN_URN"
    fi
  fi
fi
############# END: SECTION TO BE REMOVED AFTER IMAGE IS GA ###################
##############################################################################

create_image_definition() {
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
}

case ${SIG_TARGET} in
  ubuntu-2004)
    create_image_definition ${SIG_TARGET} "20_04-lts" "V1" "Linux"
  ;;
  ubuntu-2204)
    create_image_definition ${SIG_TARGET} "22_04-lts" "V1" "Linux"
  ;;
  ubuntu-2404)
    create_image_definition ${SIG_TARGET} "24_04-lts" "V1" "Linux"
  ;;
  centos-7)
    create_image_definition "centos-7" "centos-7" "V1" "Linux"
  ;;
  mariner-2)
    create_image_definition ${SIG_TARGET} "mariner-2" "V1" "Linux"
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
    create_image_definition ${SIG_TARGET} "win-2025-containerd" "V2" "Windows"
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
  ubuntu-2004-gen2)
    create_image_definition ${SIG_TARGET} "20_04-lts-gen2" "V2" "Linux"
  ;;
  ubuntu-2004-cvm)
    create_image_definition ${SIG_TARGET} "20_04-lts-cvm" "V2" "Linux" ${SECURITY_TYPE_CVM_SUPPORTED_FEATURE}
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
  centos-7-gen2)
    create_image_definition "centos-7-gen2" "centos-7-gen2" "V2" "Linux"
  ;;
  mariner-2-gen2)
    create_image_definition ${SIG_TARGET} "mariner-2-gen2" "V2" "Linux"
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
