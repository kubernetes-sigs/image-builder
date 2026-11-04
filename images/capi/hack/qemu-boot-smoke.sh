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

usage() {
  cat <<'EOF' >&2
usage: qemu-boot-smoke.sh IMAGE_OR_OUTPUT_DIR [-- QEMU_ARGS...]

Boot a local QEMU image with a copy-on-write overlay and verify that the guest
accepts SSH on a host-forwarded port. By default, a temporary NoCloud seed ISO
creates the SSH user, so the source image is not modified.

Flatcar (qemu-flatcar) images are not supported: Flatcar uses Ignition rather
than cloud-init, and the build removes the SSH user before shutdown, so no
supported QEMU_SEED value can authenticate to it. Set QEMU_IMAGE_OS=flatcar
to fail fast when invoking this helper for a Flatcar artifact.

Environment:
  QEMU_BINARY              QEMU binary to run. Default: qemu-system-x86_64
  QEMU_IMG                 qemu-img binary to run. Default: qemu-img
  QEMU_IMAGE_FORMAT        Backing image format. Default: detected by qemu-img
  QEMU_ACCELERATOR         QEMU accelerator. Default: kvm on Linux with /dev/kvm,
                           hvf on macOS, otherwise tcg. hvf/kvm are only
                           selected when QEMU_BINARY's target architecture
                           matches the host architecture; e.g. running
                           qemu-system-x86_64 on arm64 macOS defaults to tcg
  QEMU_MACHINE             QEMU machine type. Default: pc
  QEMU_CPUS                vCPU count. Default: 2
  QEMU_MEMORY              Guest memory. Default: 2048
  QEMU_SSH_PORT            Host port forwarded to guest port 22. Default: 2222
  QEMU_SSH_TIMEOUT         Seconds to wait for SSH. Default: 600
  QEMU_SSH_INTERVAL        Seconds between SSH checks. Default: 5
  QEMU_SSH_USER            SSH user to verify. Default: capi
  QEMU_SSH_PRIVATE_KEY     SSH private key. Default: cloudinit/id_rsa.capi
  QEMU_SSH_PUBLIC_KEY      SSH public key. Default: cloudinit/id_rsa.capi.pub
  QEMU_SMOKE_COMMAND       Command to run over SSH. Default: true
  QEMU_SEED                cloud-init or none. Default: cloud-init
  QEMU_IMAGE_OS            Set to flatcar to fail before an unsupported smoke
                           test is attempted. Default: unset
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
capi_dir="$(cd "${script_dir}/.." && pwd -P)"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/qemu-guest.sh
source "${script_dir}/lib/qemu-guest.sh"

image_arg="${1}"
shift

QEMU_GUEST_EXTRA_ARGS=()
if [[ ${1:-} == "--" ]]; then
  shift
  # A trailing "--" with nothing after it leaves no positional parameters, and
  # bash before 4.4 treats "${@}" as unset under nounset.
  QEMU_GUEST_EXTRA_ARGS=(${@+"${@}"})
elif [[ $# -gt 0 ]]; then
  usage
  exit 1
fi

QEMU_BINARY="${QEMU_BINARY:-qemu-system-x86_64}"
QEMU_IMG="${QEMU_IMG:-qemu-img}"
QEMU_MACHINE="${QEMU_MACHINE:-pc}"
QEMU_CPUS="${QEMU_CPUS:-2}"
QEMU_MEMORY="${QEMU_MEMORY:-2048}"
QEMU_SSH_PORT="${QEMU_SSH_PORT:-2222}"
QEMU_SSH_TIMEOUT="${QEMU_SSH_TIMEOUT:-600}"
QEMU_SSH_INTERVAL="${QEMU_SSH_INTERVAL:-5}"
QEMU_SSH_USER="${QEMU_SSH_USER:-capi}"
QEMU_SSH_PRIVATE_KEY="${QEMU_SSH_PRIVATE_KEY:-${capi_dir}/cloudinit/id_rsa.capi}"
QEMU_SSH_PUBLIC_KEY="${QEMU_SSH_PUBLIC_KEY:-${capi_dir}/cloudinit/id_rsa.capi.pub}"
QEMU_SMOKE_COMMAND="${QEMU_SMOKE_COMMAND:-true}"
QEMU_SEED="${QEMU_SEED:-cloud-init}"
QEMU_IMAGE_OS="${QEMU_IMAGE_OS:-}"

qemu_guest_require_command "${QEMU_BINARY}"
qemu_guest_require_command "${QEMU_IMG}"
qemu_guest_require_command ssh

if ! image="$(qemu_guest_resolve_image_path "${image_arg}")"; then
  exit 1
fi
if [[ "${QEMU_IMAGE_OS}" == "flatcar" ]]; then
  echo "qemu-boot-smoke.sh does not support Flatcar images: Flatcar uses Ignition, not cloud-init, and the build removes the SSH user before shutdown, so neither QEMU_SEED=cloud-init nor QEMU_SEED=none can authenticate. Image: ${image}" >&2
  exit 1
fi
if [[ ! -r "${QEMU_SSH_PRIVATE_KEY}" ]]; then
  echo "SSH private key is not readable: ${QEMU_SSH_PRIVATE_KEY}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/qemu-boot-smoke.XXXXXX")"
QEMU_GUEST_PID=""
# shellcheck disable=SC2329 # Called from the EXIT trap.
cleanup() {
  qemu_guest_stop "${QEMU_GUEST_PID}"
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT
# Ctrl-C during the SSH wait must stop the guest and remove the overlay, so turn
# the signal into an exit that runs the EXIT trap.
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

QEMU_GUEST_SEED_ARGS=()
case "${QEMU_SEED}" in
cloud-init)
  seed_iso="${tmp_dir}/cidata.iso"
  qemu_guest_write_seed_iso "${tmp_dir}/seed" "${seed_iso}" "${QEMU_SSH_USER}" "${public_key}" qemu-boot-smoke
  QEMU_GUEST_SEED_ARGS=(-drive "file=${seed_iso},media=cdrom,readonly=on")
  ;;
none) ;;
*)
  echo "unsupported QEMU_SEED=${QEMU_SEED}; expected cloud-init or none" >&2
  exit 1
  ;;
esac

QEMU_GUEST_BINARY="${QEMU_BINARY}"
QEMU_GUEST_ACCELERATOR="${QEMU_ACCELERATOR:-$(qemu_guest_detect_accelerator "${QEMU_BINARY}")}"
QEMU_GUEST_MACHINE="${QEMU_MACHINE}"
QEMU_GUEST_MEMORY="${QEMU_MEMORY}"
QEMU_GUEST_CPUS="${QEMU_CPUS}"
QEMU_GUEST_SSH_PORT="${QEMU_SSH_PORT}"
QEMU_GUEST_SSH_USER="${QEMU_SSH_USER}"
QEMU_GUEST_SSH_TIMEOUT="${QEMU_SSH_TIMEOUT}"
QEMU_GUEST_SSH_INTERVAL="${QEMU_SSH_INTERVAL}"
QEMU_GUEST_SERIAL_LOG="${tmp_dir}/serial.log"
QEMU_GUEST_PIDFILE="${tmp_dir}/qemu.pid"

qemu_guest_start
qemu_guest_wait_for_ssh "${QEMU_SMOKE_COMMAND}"
echo "QEMU boot smoke succeeded for ${image}"
