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

TARGETS=("ubuntu-1804" "ubuntu-2004" "photon-3" "centos-7")

on_exit() {
  for target in ${TARGETS[@]};
  do
    echo "----------------------"
    echo "${target} build logs"
    echo "----------------------"
    cat ${target}-${TIMESTAMP}.log
  done

  # kill the VPN
  docker kill vpn
}

cleanup_build_vm() {
  # Setup govc to delete build VM after
  curl -L https://github.com/vmware/govmomi/releases/download/v0.23.0/govc_linux_amd64.gz | gunzip > govc
  chmod +x govc
  mv govc /usr/local/bin/govc

  for target in ${TARGETS[@]};
  do
    govc vm.destroy capv-ci-${target}-${TIMESTAMP}
  done

}

trap on_exit EXIT

export PATH=${PWD}/.local/bin:$PATH
export PATH=${PYTHON_BIN_DIR:-"/root/.local/bin"}:$PATH
export GC_KIND="false"
export TIMESTAMP="$(date -u '+%Y%m%dT%H%M%S')"
export GOVC_DATACENTER="SDDC-Datacenter"
export GOVC_INSECURE=true

cat << EOF > packer/ova/vsphere.json
{
    "vcenter_server":"${GOVC_URL}",
    "insecure_connection": "${GOVC_INSECURE}",
    "username":"${GOVC_USERNAME}",
    "password":"${GOVC_PASSWORD}",
    "datastore":"WorkloadDatastore",
    "datacenter":"${GOVC_DATACENTER}",
    "cluster": "Cluster-1",
    "network": "sddc-cgw-network-8",
    "folder": "Workloads/ci/imagebuilder"
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
  gcr.io/cluster-api-provider-vsphere/extra/openvpn:latest

# Tail the vpn logs
docker logs vpn

# install deps and build all images
make deps-ova

for target in ${TARGETS[@]};
do
  if [[ "${target}" == 'photon-3' ]]; then
cat << EOF > ci-${target}.json
{
"build_version": "capv-ci-${target}-${TIMESTAMP}",
"linked_clone": "true",
"template": "base-photon-3-20211209"
}
EOF
    PACKER_VAR_FILES="ci-${target}.json" make build-node-ova-vsphere-clone-${target} > ${target}-${TIMESTAMP}.log 2>&1 &

  else
cat << EOF > ci-${target}.json
{
"build_version": "capv-ci-${target}-${TIMESTAMP}"
}
EOF
    PACKER_VAR_FILES="ci-${target}.json" make build-node-ova-vsphere-${target} > ${target}-${TIMESTAMP}.log 2>&1 &
  fi
  PIDS+=($!)
done

# need to unset errexit so that failed child tasks don't cause script to exit
set +o errexit
exit_err=false
for pid in "${PIDS[@]}"; do
  wait "${pid}"
  if [[ $? -ne 0 ]]; then
    exit_err=true
  fi
done
set -o errexit

cleanup_build_vm
if [[ "${exit_err}" = true ]]; then
  exit 1
fi
