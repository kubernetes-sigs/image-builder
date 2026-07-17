#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
capi_dir="$(cd -- "${script_dir}/.." && pwd)"

target="${NODE_CONFORMANCE_TARGET:-build-qemu-ubuntu-2404-cloudimg}"
cpus="${NODE_CONFORMANCE_CPUS:-4}"
memory="${NODE_CONFORMANCE_MEMORY:-8192}"
parallelism="${NODE_CONFORMANCE_PARALLELISM:-1}"
timeout="${NODE_CONFORMANCE_TIMEOUT:-2h}"
accelerator="${NODE_CONFORMANCE_ACCELERATOR:-kvm}"
cpu_model="${NODE_CONFORMANCE_CPU_MODEL:-host}"

if [[ "${accelerator}" == "kvm" && ! -e /dev/kvm ]]; then
  echo "NODE_CONFORMANCE_ACCELERATOR=kvm requires /dev/kvm in the CI container." >&2
  echo "Use a nested-virtualization capable runner, or set NODE_CONFORMANCE_ACCELERATOR=tcg and NODE_CONFORMANCE_CPU_MODEL=max for slow local debugging." >&2
  exit 1
fi

default_packer_flags=(
  --var "node_conformance=true"
  --var "node_conformance_parallelism=${parallelism}"
  --var "node_conformance_timeout=${timeout}"
  --var "accelerator=${accelerator}"
  --var "cpu_model=${cpu_model}"
  --var "cpus=${cpus}"
  --var "memory=${memory}"
)

printf -v joined_default_packer_flags '%q ' "${default_packer_flags[@]}"
export PACKER_FLAGS="${joined_default_packer_flags}${PACKER_FLAGS:-}"

cd "${capi_dir}"
make deps-qemu "${target}"
