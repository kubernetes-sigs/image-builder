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
TARGETS=("ubuntu-2004" "ubuntu-2204" "photon-3" "photon-4" "photon-5" "rockylinux-8" "flatcar")

on_exit() {
  #Cleanup VMs
  cleanup_build_vm

  # kill the VPN
  docker kill vpn
}

cleanup_build_vm() {
  # Setup govc to delete build VM after
  wget https://github.com/vmware/govmomi/releases/download/v0.30.5/govc_Linux_x86_64.tar.gz
  tar xf govc_Linux_x86_64.tar.gz
  chmod +x govc
  mv govc /usr/local/bin/govc

  for target in ${TARGETS[@]};
  do
    # Adding || true to both commands so it does not exit after not being able to cleanup one target.
    govc vm.power -off -force -wait /${GOVC_DATACENTER}/vm/${FOLDER}/capv-ci-${target}-${TIMESTAMP} || true
    govc object.destroy /${GOVC_DATACENTER}/vm/${FOLDER}/capv-ci-${target}-${TIMESTAMP} || true
  done

}

trap on_exit EXIT

export PATH=${PWD}/.local/bin:$PATH
export PATH=${PYTHON_BIN_DIR:-"/root/.local/bin"}:$PATH
export GC_KIND="false"
export TIMESTAMP="$(date -u '+%Y%m%dT%H%M%S')"
export GOVC_DATACENTER="SDDC-Datacenter"
export GOVC_INSECURE=true
export FOLDER="Workloads/image-builder"

echo "Running build with timestamp ${TIMESTAMP}"

cat << EOF > packer/ova/vsphere.json
{
    "vcenter_server":"${GOVC_URL}",
    "insecure_connection": "${GOVC_INSECURE}",
    "username":"${GOVC_USERNAME}",
    "password":"${GOVC_PASSWORD}",
    "datastore":"WorkloadDatastore",
    "datacenter":"${GOVC_DATACENTER}",
    "resource_pool": "Compute-ResourcePool/image-builder",
    "cluster": "Cluster-1",
    "network": "sddc-cgw-network-8",
    "folder": "${FOLDER}"
}
EOF

# Since access to esxi is blocked due to firewall rules,
# `export`, `post-processor` sections from `packer-node.json` are removed.
cat packer/ova/packer-node.json | jq  'del(.builders[] | select( .name == "vsphere" ).export)' > packer/ova/packer-node.json.tmp && mv packer/ova/packer-node.json.tmp packer/ova/packer-node.json
cat packer/ova/packer-node.json | jq  'del(.builders[] | select( .name == "vsphere-clone" ).export)' > packer/ova/packer-node.json.tmp && mv packer/ova/packer-node.json.tmp packer/ova/packer-node.json
cat packer/ova/packer-node.json | jq  'del(."post-processors"[])' > packer/ova/packer-node.json.tmp && mv packer/ova/packer-node.json.tmp packer/ova/packer-node.json

# Run the vpn client in container
docker run --rm -d --name vpn -v "${HOME}/.openvpn/:${HOME}/.openvpn/" \
  -w "${HOME}/.openvpn/" --cap-add=NET_ADMIN --net=host --device=/dev/net/tun \
  gcr.io/k8s-staging-capi-vsphere/extra/openvpn:latest

# Tail the vpn logs
docker logs vpn

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
