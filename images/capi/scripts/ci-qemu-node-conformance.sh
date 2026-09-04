#!/usr/bin/env bash

# Copyright 2026 The Kubernetes Authors.
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

# Builds a QEMU node image and then runs Kubernetes node conformance against the
# built artifact from a throwaway copy-on-write overlay, so the shipped image is
# never modified by the test.

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
capi_dir="$(cd -- "${script_dir}/.." && pwd)"

target="${NODE_CONFORMANCE_TARGET:-build-qemu-ubuntu-2404-cloudimg}"
cpus="${NODE_CONFORMANCE_CPUS:-4}"
memory="${NODE_CONFORMANCE_MEMORY:-8192}"
accelerator="${NODE_CONFORMANCE_ACCELERATOR:-kvm}"

case "${target}" in
*flatcar*)
  echo "NODE_CONFORMANCE_TARGET=${target} is not supported for node conformance; Flatcar uses Ignition and is explicitly excluded." >&2
  exit 1
  ;;
esac

if [[ "${accelerator}" == "kvm" && ! -e /dev/kvm ]]; then
  echo "NODE_CONFORMANCE_ACCELERATOR=kvm requires /dev/kvm in the CI container." >&2
  echo "Use a nested-virtualization capable runner, or set NODE_CONFORMANCE_ACCELERATOR=tcg for slow local debugging." >&2
  exit 1
fi

cd "${capi_dir}"
make deps-qemu "${target}"

# The build target writes to output/<build_name>-kube-<kubernetes_semver>. Pick
# the directory the build just produced.
output_dirs=()
while IFS= read -r output_dir; do
  output_dirs+=("${output_dir}")
done < <(find output -mindepth 1 -maxdepth 1 -type d | sort)
if [[ "${#output_dirs[@]}" -ne 1 ]]; then
  echo "expected exactly one build output directory under output/; found ${#output_dirs[@]}" >&2
  printf '%s\n' "${output_dirs[@]+"${output_dirs[@]}"}" >&2
  exit 1
fi

QEMU_ACCELERATOR="${accelerator}" \
  QEMU_CPUS="${cpus}" \
  QEMU_MEMORY="${memory}" \
  hack/qemu-node-conformance.sh "${output_dirs[0]}"
