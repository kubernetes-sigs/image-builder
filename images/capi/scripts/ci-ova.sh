#!/bin/bash

# Copyright 2020 The Kubernetes Authors.
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

set -o errexit  # exits immediately on any unexpected error (does not bypass traps)
set -o nounset  # will error if variables are used without first being defined
set -o pipefail # any non-zero exit code in a piped command causes the pipeline to fail with that code

CAPI_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
cd "${CAPI_ROOT}" || exit 1

export ARTIFACTS="${ARTIFACTS:-${PWD}/_artifacts}"
# Dynamically gets all targets and filters out the following:
# - Any RHEL targets (because of subscription requirements)
# - Any Windows targets (because of license requirements)
# - Any efi targets (to reduce duplicate OSs)
# The following are currently having issues running in the
# test environment so are specifically excluded for now
# - Photon-4
TARGETS=( $(make build-node-ova-vsphere-all --recon -d | grep "Must remake" | \
  grep -v build-node-ova-vsphere-all | \
  grep -E -v 'rhel|windows|efi' | \
  grep -v build-node-ova-vsphere-photon-4 | \
  grep -E -o 'build-node-ova-vsphere-[a-zA-Z0-9\-]+' ) )

export BOSKOS_RESOURCE_OWNER=image-builder
if [[ "${JOB_NAME}" != "" ]]; then
  export BOSKOS_RESOURCE_OWNER="${JOB_NAME}/${BUILD_ID}"
fi
export BOSKOS_RESOURCE_TYPE="gcve-vsphere-project"

on_exit() {
  # Stop boskos heartbeat
  [[ -z ${HEART_BEAT_PID:-} ]] || kill -9 "${HEART_BEAT_PID}"

  # If Boskos is being used then release the vsphere project.
  [ -z "${BOSKOS_HOST:-}" ] || docker run -e VSPHERE_USERNAME -e VSPHERE_PASSWORD gcr.io/k8s-staging-capi-vsphere/extra/boskosctl:latest release --boskos-host="${BOSKOS_HOST}" --resource-owner="${BOSKOS_RESOURCE_OWNER}" --resource-name="${BOSKOS_RESOURCE_NAME}" --vsphere-server="${VSPHERE_SERVER}" --vsphere-tls-thumbprint="${VSPHERE_TLS_THUMBPRINT}" --vsphere-folder="${BOSKOS_RESOURCE_FOLDER}" --vsphere-resource-pool="${BOSKOS_RESOURCE_POOL}"
}

trap on_exit EXIT

# For Boskos
# Sanitize input envvars to not contain newline
GOVC_USERNAME=$(echo "${GOVC_USERNAME}" | tr -d "\n")
GOVC_PASSWORD=$(echo "${GOVC_PASSWORD}" | tr -d "\n")
GOVC_URL=$(echo "${GOVC_URL}" | tr -d "\n")
VSPHERE_TLS_THUMBPRINT=$(echo "${VSPHERE_TLS_THUMBPRINT:-}" | tr -d "\n")
BOSKOS_HOST=$(echo "${BOSKOS_HOST:-}" | tr -d "\n")

export VSPHERE_SERVER="${GOVC_URL:-}"
export VSPHERE_USERNAME="${GOVC_USERNAME:-}"
export VSPHERE_PASSWORD="${GOVC_PASSWORD:-}"

export PATH=${PWD}/.local/bin:$PATH
export PATH=${PYTHON_BIN_DIR:-"/root/.local/bin"}:$PATH
export GC_KIND="false"
export TIMESTAMP="$(date -u '+%Y%m%dT%H%M%S')"
export GOVC_DATACENTER="Datacenter"
export GOVC_CLUSTER="k8s-gcve-cluster"
export GOVC_INSECURE=true

# Install xorriso which will be then used by packer to generate ISO for generating CD files
apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso

# If BOSKOS_HOST is set then acquire a vsphere-project from Boskos.
if [ -n "${BOSKOS_HOST:-}" ]; then
  # Check out the account from Boskos and store the produced environment
  # variables in a temporary file.
  account_env_var_file="$(mktemp)"
  docker run gcr.io/k8s-staging-capi-vsphere/extra/boskosctl:latest acquire --boskos-host="${BOSKOS_HOST}" --resource-owner="${BOSKOS_RESOURCE_OWNER}" --resource-type="${BOSKOS_RESOURCE_TYPE}" 1>"${account_env_var_file}"
  checkout_account_status="${?}"

  # If the checkout process was a success then load the account's
  # environment variables into this process.
  # shellcheck disable=SC1090
  [ "${checkout_account_status}" = "0" ] && . "${account_env_var_file}"
  export BOSKOS_RESOURCE_NAME=${BOSKOS_RESOURCE_NAME}
  # Drop absolute prefix because packer needs the relative path.
  export VSPHERE_FOLDER="$(echo "${BOSKOS_RESOURCE_FOLDER}" | sed "s@/${GOVC_DATACENTER}/vm/@@")"
  export VSPHERE_RESOURCE_POOL="$(echo "${BOSKOS_RESOURCE_POOL}" | sed "s@/${GOVC_DATACENTER}/host/${GOVC_CLUSTER}/Resources/@@")"

  # Always remove the account environment variable file. It contains
  # sensitive information.
  rm -f "${account_env_var_file}"

  if [ ! "${checkout_account_status}" = "0" ]; then
    echo "error getting vsphere project from Boskos" 1>&2
    exit "${checkout_account_status}"
  fi

  # Run the heartbeat to tell boskos periodically that we are still
  # using the checked out account.
  docker run gcr.io/k8s-staging-capi-vsphere/extra/boskosctl:latest heartbeat --boskos-host="${BOSKOS_HOST}" --resource-owner="${BOSKOS_RESOURCE_OWNER}" --resource-name="${BOSKOS_RESOURCE_NAME}" >>"${ARTIFACTS}/boskos-heartbeat.log" 2>&1 &
  HEART_BEAT_PID=$!
else
  echo "error getting vsphere project from Boskos, BOSKOS_HOST not set" 1>&2
  exit 1
fi

echo "Running build with timestamp ${TIMESTAMP}"

echo "Using user: ${GOVC_USERNAME}"
echo "Using relative folder: ${VSPHERE_FOLDER}"
echo "Using relative resource pool: ${VSPHERE_RESOURCE_POOL}"

cat << EOF > packer/ova/vsphere.json
{
    "vcenter_server":"${GOVC_URL}",
    "insecure_connection": "${GOVC_INSECURE}",
    "username":"${GOVC_USERNAME}",
    "password":"${GOVC_PASSWORD}",
    "datastore":"vsanDatastore",
    "datacenter":"${GOVC_DATACENTER}",
    "resource_pool": "${VSPHERE_RESOURCE_POOL}",
    "cluster": "${GOVC_CLUSTER}",
    "network": "k8s-ci",
    "folder": "${VSPHERE_FOLDER}"
}
EOF

# Since access to esxi is blocked due to firewall rules,
# `export`, `post-processor` sections from `packer-node.json` are removed.
cat packer/ova/packer-node.json | jq  'del(.builders[] | select( .name == "vsphere" ).export)' > packer/ova/packer-node.json.tmp && mv packer/ova/packer-node.json.tmp packer/ova/packer-node.json
cat packer/ova/packer-node.json | jq  'del(.builders[] | select( .name == "vsphere-clone" ).export)' > packer/ova/packer-node.json.tmp && mv packer/ova/packer-node.json.tmp packer/ova/packer-node.json
cat packer/ova/packer-node.json | jq  'del(."post-processors"[])' > packer/ova/packer-node.json.tmp && mv packer/ova/packer-node.json.tmp packer/ova/packer-node.json

# install deps and build all images
make deps-ova

declare -A PIDS
for target in ${TARGETS[@]};
do
  target=${target#build-node-ova-vsphere-}
  export PACKER_VAR_FILES="ci-${target}.json scripts/ci-disable-goss-inspect.json"
cat << EOF > ci-${target}.json
{
"build_version": "capv-ci-${target}-${TIMESTAMP}"
}
EOF
  export PACKER_LOG=1
  make build-node-ova-vsphere-${target} > ${ARTIFACTS}/${target}.log 2>&1 &
  PIDS["${target}"]=$!
done

# need to unset errexit so that failed child tasks don't cause script to exit
set +o errexit
exit_err=false
for target in "${!PIDS[@]}"; do
  wait "${PIDS[$target]}"
  if [[ $? -ne 0 ]]; then
    exit_err=true
    echo "${target}: FAILED. See logs in the artifacts folder."
  else
    echo "${target}: SUCCESS"
  fi
done
set -o errexit

if [[ "${exit_err}" = true ]]; then
  exit 1
fi
