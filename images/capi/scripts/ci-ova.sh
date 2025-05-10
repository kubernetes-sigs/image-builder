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
TARGETS=("ubuntu-2004" "ubuntu-2204" "ubuntu-2404" "photon-3" "photon-4" "photon-5" "rockylinux-8" "flatcar")

export BOSKOS_RESOURCE_OWNER=image-builder
if [[ "${JOB_NAME}" != "" ]]; then
  export BOSKOS_RESOURCE_OWNER="${JOB_NAME}/${BUILD_ID}"
fi
export BOSKOS_RESOURCE_TYPE=vsphere-project-image-builder

on_exit() {
  #Cleanup VMs
  cleanup_build_vm

  # Stop boskos heartbeat
  [[ -z ${HEART_BEAT_PID:-} ]] || kill -9 "${HEART_BEAT_PID}"

  # If Boskos is being used then release the vsphere project.
  [ -z "${BOSKOS_HOST:-}" ] || docker run -e VSPHERE_USERNAME -e VSPHERE_PASSWORD gcr.io/k8s-staging-capi-vsphere/extra/boskosctl:latest release --boskos-host="${BOSKOS_HOST}" --resource-owner="${BOSKOS_RESOURCE_OWNER}" --resource-name="${BOSKOS_RESOURCE_NAME}" --vsphere-server="${VSPHERE_SERVER}" --vsphere-tls-thumbprint="${VSPHERE_TLS_THUMBPRINT}" --vsphere-folder="${BOSKOS_RESOURCE_FOLDER}" --vsphere-resource-pool="${BOSKOS_RESOURCE_POOL}"

  # kill the VPN
  docker kill vpn
}

cleanup_build_vm() {
  # Setup govc to delete build VM after
  GOVC_VERSION=v0.49.0
  GOVC_SHA256=a33d4b11ce10e8d1bfb89ef5ea1904a416df13111b409b89d7e29308ff584272

  wget https://github.com/vmware/govmomi/releases/download/${GOVC_VERSION}/govc_Linux_x86_64.tar.gz
  echo "${GOVC_SHA256} govc_Linux_x86_64.tar.gz" | sha256sum -c
  if [[ $? -ne 0 ]]; then
     echo "FATAL: checksum for govc_Linux_x86_64.tar.gz failed"
     exit 1
  fi

  tar xf govc_Linux_x86_64.tar.gz govc
  chmod +x govc
  mv govc /usr/local/bin/govc

  for target in ${TARGETS[@]};
  do
    # Adding || true to both commands so it does not exit after not being able to cleanup one target.
    govc vm.power -off -force -wait /${GOVC_DATACENTER}/vm/${VSPHERE_FOLDER}/capv-ci-${target}-${TIMESTAMP} || true
    govc object.destroy /${GOVC_DATACENTER}/vm/${VSPHERE_FOLDER}/capv-ci-${target}-${TIMESTAMP} || true
  done

}

trap on_exit EXIT

# For Boskos
export VSPHERE_SERVER="${GOVC_URL:-}"
export VSPHERE_USERNAME="${GOVC_USERNAME:-}"
export VSPHERE_PASSWORD="${GOVC_PASSWORD:-}"

export PATH=${PWD}/.local/bin:$PATH
export PATH=${PYTHON_BIN_DIR:-"/root/.local/bin"}:$PATH
export GC_KIND="false"
export TIMESTAMP="$(date -u '+%Y%m%dT%H%M%S')"
export GOVC_DATACENTER="SDDC-Datacenter"
export GOVC_CLUSTER="Cluster-1"
export GOVC_INSECURE=true

# Install xorriso which will be then used by packer to generate ISO for generating CD files
apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso

# Run the vpn client in container
docker run --rm -d --name vpn -v "${HOME}/.openvpn/:${HOME}/.openvpn/" \
  -w "${HOME}/.openvpn/" --cap-add=NET_ADMIN --net=host --device=/dev/net/tun \
  gcr.io/k8s-staging-capi-vsphere/extra/openvpn:latest

# Tail the vpn logs
docker logs vpn

# Wait until the VPN connection is active.
function wait_for_vpn_up() {
  local n=0
  until [ $n -ge 30 ]; do
    curl "https://${VSPHERE_SERVER}" --connect-timeout 2 -k && RET=$? || RET=$?
    if [[ "$RET" -eq 0 ]]; then
      break
    fi
    n=$((n + 1))
    sleep 1
  done
  return "$RET"
}
wait_for_vpn_up

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
    "datastore":"WorkloadDatastore",
    "datacenter":"${GOVC_DATACENTER}",
    "resource_pool": "${VSPHERE_RESOURCE_POOL}",
    "cluster": "${GOVC_CLUSTER}",
    "network": "sddc-cgw-network-10",
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
  export PACKER_VAR_FILES="ci-${target}.json scripts/ci-disable-goss-inspect.json"
  if [[ "${target}" == 'photon-'* || "${target}" == 'rockylinux-8' || "${target}" == 'ubuntu-2204' ]]; then
cat << EOF > ci-${target}.json
{
"build_version": "capv-ci-${target}-${TIMESTAMP}",
"linked_clone": "true",
"template": "base-${target}"
}
EOF
    make build-node-ova-vsphere-clone-${target} > ${ARTIFACTS}/${target}.log 2>&1 &

  else
cat << EOF > ci-${target}.json
{
"build_version": "capv-ci-${target}-${TIMESTAMP}"
}
EOF
    make build-node-ova-vsphere-${target} > ${ARTIFACTS}/${target}.log 2>&1 &
  fi
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
