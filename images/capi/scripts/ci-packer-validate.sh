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

###############################################################################

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

CAPI_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
cd "${CAPI_ROOT}" || exit 1

export PATH=${PWD}/.local/bin:$PATH
export PATH=${PYTHON_BIN_DIR:-"${HOME}/.local/bin"}:$PATH

# OCI packer builder requires a valid private key file, hence creating a temporary one
openssl genrsa -out /tmp/oci_api_key.pem 2048

AZURE_LOCATION=fake RESOURCE_GROUP_NAME=fake STORAGE_ACCOUNT_NAME=fake \
  DIGITALOCEAN_ACCESS_TOKEN=fake GCP_PROJECT_ID=fake \
  OCI_AVAILABILITY_DOMAIN=fake OCI_SUBNET_OCID=fake OCI_USER_FINGERPRINT=fake \
  OCI_TENANCY_OCID=fake OCI_USER_OCID=fake OCI_USER_KEY_FILE=/tmp/oci_api_key.pem \
  NUTANIX_ENDPOINT=fake NUTANIX_CLUSTER_NAME=fake NUTANIX_USERNAME=fake \
  NUTANIX_PASSWORD=fake NUTANIX_SUBNET_NAME=fake \
  HCLOUD_LOCATION=fake HCLOUD_TOKEN=fake \
  SCW_ACCESS_KEY=fake SCW_PROJECT_ID=fake SCW_SECRET_KEY=fake \
  make validate-all
