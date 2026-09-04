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

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
capi_dir="$(cd "${script_dir}/.." && pwd -P)"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/qemu-guest.sh
source "${script_dir}/lib/qemu-guest.sh"

usage() {
  cat <<'EOF' >&2
usage: qemu-node-conformance.sh IMAGE_OR_OUTPUT_DIR [-- QEMU_ARGS...]

Run the Kubernetes e2e_node.test conformance subset against an already built
QEMU image. The image is booted from a throwaway qcow2 copy-on-write overlay
with a NoCloud seed ISO, the conformance hook is copied in over SSH, results are
copied back out, and the overlay is discarded. The built image is only ever read
from, so a conformance run cannot leave test state in the shipped artifact.

Flatcar (qemu-flatcar) images are not supported: Flatcar uses Ignition rather
than cloud-init, and the build removes the SSH user before shutdown, so the
guest cannot be reached over SSH.

Environment:
  QEMU_BINARY                      QEMU binary. Default: qemu-system-x86_64
  QEMU_IMG                         qemu-img binary. Default: qemu-img
  QEMU_IMAGE_FORMAT                Backing image format. Default: detected
  QEMU_ACCELERATOR                 QEMU accelerator. Default: kvm on Linux with
                                   /dev/kvm, hvf on macOS when the QEMU target
                                   architecture matches the host, else tcg
  QEMU_MACHINE                     QEMU machine type. Default: pc
  QEMU_CPUS                        vCPU count. Default: 4
  QEMU_MEMORY                      Guest memory in MiB. Default: 4096
  QEMU_SSH_PORT                    Host port forwarded to guest 22. Default: 2222
  QEMU_SSH_TIMEOUT                 Seconds to wait for SSH. Default: 900
  QEMU_SSH_INTERVAL                Seconds between SSH checks. Default: 5
  QEMU_SSH_USER                    SSH user. Default: capi
  QEMU_SSH_PRIVATE_KEY             SSH private key. Default: cloudinit/id_rsa.capi
  QEMU_SSH_PUBLIC_KEY              SSH public key. Default: cloudinit/id_rsa.capi.pub
  QEMU_IMAGE_OS                    Set to flatcar to fail fast. Default: unset
  NODE_CONFORMANCE_OUTPUT_DIR      Host directory for downloaded results.
                                   Default: node-conformance-results
  NODE_CONFORMANCE_RESULTS_DIR     Guest results directory.
                                   Default: /tmp/kubernetes-node-conformance-results
  KUBERNETES_VERSION               Version of the test tarball to download.
                                   Default: detected from the guest kubelet
  NODE_CONFORMANCE_FOCUS           Ginkgo focus. Default: \[Conformance\]
  NODE_CONFORMANCE_SKIP            Ginkgo skip. Default: \[Flaky\]|\[Slow\]
  NODE_CONFORMANCE_PARALLELISM     Ginkgo nodes. Default: 1
  NODE_CONFORMANCE_FLAKE_ATTEMPTS  Ginkgo flake attempts. Default: 1
  NODE_CONFORMANCE_TIMEOUT         Ginkgo timeout. Default: 2h
  NODE_CONFORMANCE_STANDALONE_MODE Run kubelet without a test apiserver.
                                   Default: false
  NODE_CONFORMANCE_KUBELET_FLAGS   Extra kubelet flags. Default:
                                   --fail-swap-on=false
                                   --runtime-cgroups=/system.slice/containerd.service
  NODE_CONFORMANCE_ETCD_VERSION    etcd to download when absent. Default: v3.5.32
EOF
}

# node_conformance_summary_exit_code prints the exit code the guest hook
# recorded. A summary that is missing or that does not report an exit code is a
# failure, never an implicit pass.
node_conformance_summary_exit_code() {
  local summary_file="${1}"
  local exit_code

  if [[ ! -f "${summary_file}" ]]; then
    echo "missing node conformance summary: ${summary_file}" >&2
    return 1
  fi

  exit_code="$(sed -n 's/^exit_code=\([0-9][0-9]*\)$/\1/p' "${summary_file}" | tail -n 1)"
  if [[ -z "${exit_code}" ]]; then
    echo "node conformance summary does not report an exit_code: ${summary_file}" >&2
    return 1
  fi

  printf '%s\n' "${exit_code}"
}

# node_conformance_guest_env prints the shell-quoted environment assignments
# forwarded into the guest. Only variables the caller set are forwarded, so the
# hook keeps its own documented defaults.
node_conformance_guest_env() {
  local -a assignments=("NODE_CONFORMANCE_RESULTS_DIR=${1}")
  local name

  for name in \
    KUBERNETES_VERSION \
    NODE_CONFORMANCE_ETCD_VERSION \
    NODE_CONFORMANCE_FLAKE_ATTEMPTS \
    NODE_CONFORMANCE_FOCUS \
    NODE_CONFORMANCE_KUBELET_FLAGS \
    NODE_CONFORMANCE_PARALLELISM \
    NODE_CONFORMANCE_SKIP \
    NODE_CONFORMANCE_STANDALONE_MODE \
    NODE_CONFORMANCE_TIMEOUT; do
    if [[ -n "${!name:-}" ]]; then
      assignments+=("${name}=${!name}")
    fi
  done

  printf '%q ' "${assignments[@]}"
}

# shellcheck disable=SC2329 # Called from the EXIT trap.
cleanup() {
  qemu_guest_stop "${QEMU_GUEST_PID:-}"
  rm -rf "${tmp_dir}"
}

main() {
  local image_arg
  local image
  local public_key
  local backing_format
  local seed_iso
  local guest_results_dir
  local hook_script
  local output_dir
  local run_dir
  local remote_hook
  local remote_env_args
  local run_status=0
  local download_status=0
  local exit_code

  if [[ $# -lt 1 ]]; then
    usage
    return 1
  fi

  image_arg="${1}"
  shift

  QEMU_GUEST_EXTRA_ARGS=()
  if [[ ${1:-} == "--" ]]; then
    shift
    # A trailing "--" with nothing after it leaves no positional parameters,
    # and bash before 4.4 treats "${@}" as unset under nounset.
    QEMU_GUEST_EXTRA_ARGS=(${@+"${@}"})
  elif [[ $# -gt 0 ]]; then
    usage
    return 1
  fi

  QEMU_BINARY="${QEMU_BINARY:-qemu-system-x86_64}"
  QEMU_IMG="${QEMU_IMG:-qemu-img}"
  guest_results_dir="${NODE_CONFORMANCE_RESULTS_DIR:-/tmp/kubernetes-node-conformance-results}"
  output_dir="${NODE_CONFORMANCE_OUTPUT_DIR:-${capi_dir}/node-conformance-results}"
  hook_script="${script_dir}/run-e2e-node-conformance.sh"

  qemu_guest_require_command "${QEMU_BINARY}"
  qemu_guest_require_command "${QEMU_IMG}"
  qemu_guest_require_command ssh
  qemu_guest_require_command scp

  if ! image="$(qemu_guest_resolve_image_path "${image_arg}")"; then
    return 1
  fi
  if [[ "${QEMU_IMAGE_OS:-}" == "flatcar" ]]; then
    echo "qemu-node-conformance.sh does not support Flatcar images: Flatcar uses Ignition, not cloud-init, and the build removes the SSH user before shutdown, so the guest cannot be reached over SSH. Image: ${image}" >&2
    return 1
  fi

  QEMU_SSH_PRIVATE_KEY="${QEMU_SSH_PRIVATE_KEY:-${capi_dir}/cloudinit/id_rsa.capi}"
  QEMU_SSH_PUBLIC_KEY="${QEMU_SSH_PUBLIC_KEY:-${capi_dir}/cloudinit/id_rsa.capi.pub}"
  if [[ ! -r "${QEMU_SSH_PRIVATE_KEY}" ]]; then
    echo "SSH private key is not readable: ${QEMU_SSH_PRIVATE_KEY}" >&2
    return 1
  fi
  if [[ ! -r "${hook_script}" ]]; then
    echo "conformance hook is not readable: ${hook_script}" >&2
    return 1
  fi

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/qemu-node-conformance.XXXXXX")"
  QEMU_GUEST_PID=""
  trap cleanup EXIT
  # Ctrl-C during the SSH wait or the conformance run must stop the guest and
  # remove the overlay, so turn the signal into an exit that runs the EXIT trap.
  trap 'exit 130' INT TERM

  QEMU_GUEST_SSH_KEY="${tmp_dir}/ssh_key"
  cp "${QEMU_SSH_PRIVATE_KEY}" "${QEMU_GUEST_SSH_KEY}"
  chmod 0600 "${QEMU_GUEST_SSH_KEY}"

  if [[ -r "${QEMU_SSH_PUBLIC_KEY}" ]]; then
    public_key="$(cat "${QEMU_SSH_PUBLIC_KEY}")"
  else
    qemu_guest_require_command ssh-keygen
    public_key="$(ssh-keygen -y -f "${QEMU_GUEST_SSH_KEY}")"
  fi

  backing_format="${QEMU_IMAGE_FORMAT:-$(qemu_guest_detect_image_format "${QEMU_IMG}" "${image}")}"
  QEMU_GUEST_DISK="${tmp_dir}/disk.qcow2"
  qemu_guest_create_overlay "${QEMU_IMG}" "${image}" "${backing_format}" "${QEMU_GUEST_DISK}"

  seed_iso="${tmp_dir}/cidata.iso"
  QEMU_GUEST_SSH_USER="${QEMU_SSH_USER:-capi}"
  qemu_guest_write_seed_iso \
    "${tmp_dir}/seed" "${seed_iso}" "${QEMU_GUEST_SSH_USER}" "${public_key}" qemu-node-conformance
  QEMU_GUEST_SEED_ARGS=(-drive "file=${seed_iso},media=cdrom,readonly=on")

  QEMU_GUEST_BINARY="${QEMU_BINARY}"
  QEMU_GUEST_ACCELERATOR="${QEMU_ACCELERATOR:-$(qemu_guest_detect_accelerator "${QEMU_BINARY}")}"
  QEMU_GUEST_MACHINE="${QEMU_MACHINE:-pc}"
  QEMU_GUEST_MEMORY="${QEMU_MEMORY:-4096}"
  QEMU_GUEST_CPUS="${QEMU_CPUS:-4}"
  QEMU_GUEST_SSH_PORT="${QEMU_SSH_PORT:-2222}"
  QEMU_GUEST_SSH_TIMEOUT="${QEMU_SSH_TIMEOUT:-900}"
  QEMU_GUEST_SSH_INTERVAL="${QEMU_SSH_INTERVAL:-5}"
  QEMU_GUEST_SERIAL_LOG="${tmp_dir}/serial.log"
  QEMU_GUEST_PIDFILE="${tmp_dir}/qemu.pid"

  echo "Booting ${image} on a throwaway overlay for node conformance"
  qemu_guest_start
  qemu_guest_wait_for_ssh true

  remote_hook="run-e2e-node-conformance.sh"
  qemu_guest_scp "${hook_script}" "guest:${remote_hook}"

  remote_env_args="$(node_conformance_guest_env "${guest_results_dir}")"
  qemu_guest_ssh "env ${remote_env_args}bash ${remote_hook}" || run_status=$?

  # Download the results before evaluating them so logs and JUnit reports
  # survive a failing run. The download lands in the throwaway directory first,
  # then it is copied into a fresh per-run subdirectory of the output
  # directory. NODE_CONFORMANCE_OUTPUT_DIR is caller supplied, so nothing under
  # it is ever deleted and repeated runs accumulate side by side.
  qemu_guest_scp "guest:${guest_results_dir}" "${tmp_dir}/results" || download_status=$?
  if [[ "${download_status}" -ne 0 ]]; then
    echo "failed to download node conformance results from the guest" >&2
    qemu_guest_dump_serial_log
    return 1
  fi

  mkdir -p "${output_dir}"
  run_dir="$(mktemp -d "${output_dir}/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  cp -R "${tmp_dir}/results/." "${run_dir}/"
  echo "Node conformance results downloaded to ${run_dir}"

  exit_code="$(node_conformance_summary_exit_code "${run_dir}/summary.env")" || return 1
  if [[ "${exit_code}" != "0" || "${run_status}" -ne 0 ]]; then
    echo "node conformance failed: hook exit_code=${exit_code}, ssh status=${run_status}" >&2
    return 1
  fi

  echo "Node conformance succeeded for ${image}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
