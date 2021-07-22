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

which pub &> /dev/null || (echo "Please install pub from https://github.com/devigned/pub/releases" && exit 1)

# Get URLs in use by the marketplace offers
URLS=""
for name in ${OFFERS}; do
  echo "Getting URLs for ${name}..."
  offer=$(pub offers show -p "$PUBLISHER" -o "$name")
  urls=$(echo "${offer}" | jq '.definition["plans"][]."microsoft-azure-corevm.vmImagesPublicAzure"[]?.osVhdUrl')
  if [[ -z $URLS ]]; then
    URLS=${urls}
  else
    URLS=${URLS}$'\n'${urls}
  fi
done
NOW=$(date +%s)

IFS=$'\n'
deleted=0
# For each storage account in the subscription,
for account in $(az storage account list -g "${RESOURCE_GROUP}" -o tsv --query "[?starts_with(name, '${PREFIX}')].[name,creationTime]"); do
  IFS=$'\t' read -r storage_account creation_time <<< "$account"
  created=$(date -d "${creation_time}" +%s 2>/dev/null || date -j -f "%F" "${creation_time}" +%s 2>/dev/null)
  age=$(( (NOW - created) / 86400 ))
  # if it's older than a month
  if [[ $age -gt 30 ]]; then
    # and it has the right naming pattern but isn't referenced in the offer osVhdUrls
    if [[ ${storage_account} =~ ^${LONG_PREFIX} ]] && [[ ! ${URLS} =~ ${storage_account} ]]; then
        # delete it.
        echo "Deleting unreferenced storage account ${storage_account} that is ${age} days old"
        # NOTE: Remove the "echo" to enable deletion of storage accounts.
        echo az storage account delete -g "${RESOURCE_GROUP}" -n "${storage_account}" # -y
        deleted=$((deleted+1))
    fi
  fi
done

echo "Deleted ${deleted} storage accounts."
