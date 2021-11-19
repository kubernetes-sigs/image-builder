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
# building CAPZ reference images.
# By default, it will only print the commands it would have run. Remove the
# "echo" statement near the bottom of the file to enable deletion.

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

RESOURCE_GROUP=${RESOURCE_GROUP:-cluster-api-images}
PUBLISHER=${PUBLISHER:-cncf-upstream}
OFFERS=${OFFERS:-capi capi-windows}
PREFIX=${PREFIX:-capi}
LONG_PREFIX=${LONG_PREFIX:-${PREFIX}[0-9]{10\}}
ARCHIVE_STORAGE_ACCOUNT=${ARCHIVE_STORAGE_ACCOUNT:-${PREFIX}archive}

which pub &> /dev/null || (echo "Please install pub from https://github.com/devigned/pub/releases" && exit 1)

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
echo "Creating storage account ${ARCHIVE_STORAGE_ACCOUNT}..."
az storage account create -g "${RESOURCE_GROUP}" -n "${ARCHIVE_STORAGE_ACCOUNT}" --sku Standard_LRS 

IFS=$'\n'
archived=0
deleted=0
# For each storage account in the subscription,
for account in $(az storage account list -g "${RESOURCE_GROUP}" -o tsv --query "[?starts_with(name, '${PREFIX}')].[name,creationTime]"); do
  IFS=$'\t' read -r storage_account creation_time <<< "$account"
  created=$(date -d "${creation_time}" +%s 2>/dev/null || date -j -f "%F" "${creation_time}" +%s 2>/dev/null)
  age=$(( (NOW - created) / 86400 ))
  # if it's older than a month
  if [[ $age -gt 30 ]]; then
    # and it has the right naming pattern
    if [[ ${storage_account} =~ ^${LONG_PREFIX} ]]; then
      # but isn't referenced in the offer osVhdUrls
      if [[ ! ${URLS} =~ ${storage_account} ]]; then
        # delete it.
        echo "Deleting unreferenced storage account ${storage_account} that is ${age} days old"
        # NOTE: Remove the "echo" to enable deletion of storage accounts.
        echo az storage account delete -g "${RESOURCE_GROUP}" -n "${storage_account}" -y
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
            az storage container create --only-show-errors \
              --name ${dest_label} --account-name "${ARCHIVE_STORAGE_ACCOUNT}"
            # for each source container
            for container in $(az storage container list --only-show-errors --account-name ${storage_account} --query "[].name" -o tsv); do
              # copy it to the destination container
              # NOTE: Remove "--dryrun" to enable blob copying.
              az storage blob copy start-batch --dryrun \
                --account-name capiarchive \
                --destination-container ${dest_label} \
                --destination-path ${container} \
                --source-container ${container} \
                --source-account-name ${storage_account} \
                --pattern '*capi-*'
              # TODO: poll new container until it is complete
              sleep 10
              az storage blob list --only-show-errors \
                --container-name ${dest_label} \
                --account-name capiarchive \
                --prefix ${container} \
                -o tsv
            done
            # NOTE: Remove the "echo" to enable deletion of storage accounts.
            echo az storage account delete -g "${RESOURCE_GROUP}" -n "${storage_account}" -y
            archived=$((archived+1))
          fi
        done
      fi
    fi
  fi
done

echo "Deleted ${deleted} storage accounts."
echo "Archived ${archived} storage accounts."
