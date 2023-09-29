#!/bin/bash
# Copyright 2021 The Kubernetes Authors.
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

# This script deletes unused Azure storage accounts created in the process of
# building CAPZ reference images. It also archives existing accounts into one
# main storage account to reduce the limited number of accounts in use.
# Usage:
#  <DRY_RUN=true|false> delete-unused-storage.sh
#
# The `pub` tool (https://github.com/devigned/pub) and the `az` CLI tool
# (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) must be found
# in the PATH.
#
# In order to run this script, log in to the publishing account with the
# `az account set -s <SUBSCRIPTION_ID>` command. Then export these environment
# variables to enable access to the storage accounts:
#   AZURE_CLIENT_ID
#   AZURE_CLIENT_SECRET
#   AZURE_SUBSCRIPTION_ID
#   AZURE_TENANT_ID
#
# By default, the script will not modify any resources. Pass the environment variable
# DRY_RUN=false to enable the script to archive and to delete the storage accounts.

set -o errexit
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

RESOURCE_GROUP=${RESOURCE_GROUP:-cluster-api-images}
PUBLISHER=${PUBLISHER:-cncf-upstream}
OFFERS=${OFFERS:-capi capi-windows}
PREFIX=${PREFIX:-capi}
LONG_PREFIX=${LONG_PREFIX:-${PREFIX}[0-9]{10\}}
ARCHIVE_STORAGE_ACCOUNT=${ARCHIVE_STORAGE_ACCOUNT:-${PREFIX}archive}
DAYS_OLD=${DAYS_OLD:-30}
DRY_RUN=${DRY_RUN:-true}
PUB_VERSION=${PUB_VERSION:-"v0.3.3"}
RED='\033[0;31m'
NC='\033[0m'

required_env_vars=(
    "AZURE_CLIENT_ID"
    "AZURE_CLIENT_SECRET"
    "AZURE_TENANT_ID"
    "AZURE_CLIENT_ID_VHD"
    "AZURE_CLIENT_SECRET_VHD"
    "AZURE_SUBSCRIPTION_ID_VHD"
    "AZURE_TENANT_ID_VHD"
)

for v in "${required_env_vars[@]}"
do
    if [ -z "${!v}" ]; then
        echo "$v was not set!"
        exit 1
    fi
done

set -o nounset

if ${DRY_RUN}; then
  echo "DRY_RUN: This script will not copy or delete any resources."
  ECHO=echo
else
  ECHO=
fi

echo "Getting pub..."
curl -fsSL https://github.com/devigned/pub/releases/download/${PUB_VERSION}/pub_${PUB_VERSION}_linux_amd64.tar.gz -o pub.tgz; tar -xzf pub.tgz; mv ./pub_linux_amd64 ./pub
export PATH=$PATH:$(pwd)
which pub &> /dev/null || (echo "Please install pub from https://github.com/devigned/pub/releases" && exit 1)

az login --service-principal -u ${AZURE_CLIENT_ID_VHD} -p ${AZURE_CLIENT_SECRET_VHD} --tenant ${AZURE_TENANT_ID_VHD}
az account set -s ${AZURE_SUBSCRIPTION_ID_VHD}

# Get URLs in use by the marketplace offers
URLS=""
for name in ${OFFERS}; do
  echo "Getting URLs for ${name}..."
  offer=$(pub offers show -p "$PUBLISHER" -o "$name")
  # Capture "label" as well as "osVhdUrl" so we can archive storage accounts with something readable.
  urls=$(echo "${offer}" | jq -r '.definition["plans"][]."microsoft-azure-corevm.vmImagesPublicAzure"[] | [.label, .osVhdUrl] | @csv')
  if [[ -z $URLS ]]; then
    URLS=${urls}
  else
    URLS=${URLS}$'\n'${urls}
  fi
done
NOW=$(date +%s)

# ensure the existence of the archive storage account
if ! az storage account show -g "${RESOURCE_GROUP}" -n "${ARCHIVE_STORAGE_ACCOUNT}" &> /dev/null; then
  echo "Creating archive storage account ${ARCHIVE_STORAGE_ACCOUNT}..."
  $ECHO az storage account create -g "${RESOURCE_GROUP}" -n "${ARCHIVE_STORAGE_ACCOUNT}" --access-tier Cool --allow-blob-public-access false
fi

IFS=$'\n'
archived=0
deleted=0
# For each storage account in the subscription,
for account in $(az storage account list -g "${RESOURCE_GROUP}" -o tsv --query "[?starts_with(name, '${PREFIX}')].[name,creationTime]"); do
  IFS=$'\t' read -r storage_account creation_time <<< "$account"
  created=$(date -d "${creation_time}" +%s 2>/dev/null || date -j -f "%F" "${creation_time}" +%s 2>/dev/null)
  age=$(( (NOW - created) / 86400 ))
  # if it's too old
  if [[ $age -gt ${DAYS_OLD} ]]; then
    # and it has the right naming pattern
    if [[ ${storage_account} =~ ^${LONG_PREFIX} ]]; then
      # but isn't referenced in the offer osVhdUrls
      if [[ ! ${URLS} =~ ${storage_account} ]]; then
        # delete it.
        echo "Deleting unreferenced storage account ${storage_account} that is ${age} days old"
        ${ECHO} az storage account delete -g "${RESOURCE_GROUP}" -n "${storage_account}" -y
        deleted=$((deleted+1))
      else
        # archive it.
        for URL in ${URLS}; do
          IFS=$',' read -r label url <<< "${URL}"
          # container names are somewhat strict, so transform the label into a valid container name
          # See https://github.com/MicrosoftDocs/azure-docs/blob/master/includes/storage-container-naming-rules-include.md
          dest_label=${label//[ .]/-}
          dest_label=${dest_label//[^a-zA-Z0-9-]/}
          dest_label=$(echo "${dest_label}" | tr '[:upper:]' '[:lower:]')
          if [[ ${url} =~ ${storage_account} ]]; then
            echo "Archiving storage account ${storage_account} (${label}) that is ${age} days old"
            # create a destination container
            if [[ $(az storage container exists --account-name "${ARCHIVE_STORAGE_ACCOUNT}" -n "${dest_label}" -o tsv 2>/dev/null) != "True" ]]; then
              ${ECHO} az storage container create --only-show-errors --public-access=container \
                -n ${dest_label} -g "${RESOURCE_GROUP}" --account-name "${ARCHIVE_STORAGE_ACCOUNT}" 2>/dev/null
            fi
            # for each source container
            for container in $(az storage container list --only-show-errors --account-name ${storage_account} --query "[].name" -o tsv 2>/dev/null); do
              # copy it to the destination container
              ${ECHO} az storage blob copy start-batch \
                --account-name ${ARCHIVE_STORAGE_ACCOUNT} \
                --destination-container ${dest_label} \
                --destination-path ${container} \
                --source-container ${container} \
                --source-account-name ${storage_account} \
                --pattern '*capi-*' \
                2>/dev/null
            done
            # poll the target container until all blobs have "succeeded" copy status
            for target in $(az storage blob list --account-name ${ARCHIVE_STORAGE_ACCOUNT} -c ${dest_label} --query '[].name' -o tsv 2>/dev/null); do
              while true; do
                status=$(az storage blob show --account-name ${ARCHIVE_STORAGE_ACCOUNT} --container-name ${dest_label} --name $target -o tsv --query 'properties.copy.status' 2>/dev/null)
                if [[ ${status} == "success" ]]; then
                  echo "Copied ${dest_label}/${target}"
                  break
                else
                  echo "Copying ${dest_label}/${target} ..."
                  sleep 20
                fi
              done
            done
            echo "Deleting source storage account ${storage_account}..."
            ${ECHO} az storage account delete -g "${RESOURCE_GROUP}" -n "${storage_account}" -y
            archived=$((archived+1))
          fi
        done
        echo -e "Pausing for 10 seconds. ${RED}Hit Ctrl-C to stop.${NC}"
        sleep 10
        echo
      fi
    fi
  fi
done

echo "Deleted ${deleted} storage accounts."
echo "Archived ${archived} storage accounts."
