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

Environment:
  QEMU_BINARY              QEMU binary to run. Default: qemu-system-x86_64
  QEMU_IMG                 qemu-img binary to run. Default: qemu-img
  QEMU_IMAGE_FORMAT        Backing image format. Default: detected by qemu-img
  QEMU_ACCELERATOR         QEMU accelerator. Default: kvm on Linux with /dev/kvm,
                           hvf on macOS, otherwise tcg
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
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
capi_dir="$(cd "${script_dir}/.." && pwd -P)"

image_arg="${1}"
shift

qemu_extra_args=()
if [[ ${1:-} == "--" ]]; then
  shift
  qemu_extra_args=("${@}")
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

require_command() {
  if ! command -v "${1}" >/dev/null 2>&1; then
    echo "${1} must be in PATH" >&2
    exit 1
  fi
}

abs_path() {
  local path="${1}"
  local dir
  local base

  dir="$(dirname "${path}")"
  base="$(basename "${path}")"
  echo "$(cd "${dir}" && pwd -P)/${base}"
}

resolve_image() {
  local input="${1}"
  local matches
  local count

  if [[ -d "${input}" ]]; then
    matches="$(find "${input}" -maxdepth 1 -type f \( -name "*.qcow2" -o -name "*.raw" -o -name "*.img" \) -print | sort)"
    count="$(printf '%s\n' "${matches}" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "${count}" != "1" ]]; then
      echo "expected exactly one *.qcow2, *.raw, or *.img file in ${input}; found ${count}" >&2
      exit 1
    fi
    printf '%s\n' "${matches}"
    return
  fi

  if [[ ! -f "${input}" ]]; then
    echo "image does not exist: ${input}" >&2
    exit 1
  fi

  printf '%s\n' "${input}"
}

detect_accelerator() {
  case "$(uname -s)" in
  Linux)
    if [[ -r /dev/kvm && -w /dev/kvm ]]; then
      echo kvm
    else
      echo tcg
    fi
    ;;
  Darwin)
    echo hvf
    ;;
  *)
    echo tcg
    ;;
  esac
}

detect_image_format() {
  local image="${1}"
  local format

  require_command python3
  format="$("${QEMU_IMG}" info --output=json "${image}" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("format", ""))')"
  if [[ -z "${format}" ]]; then
    echo "could not detect image format for ${image}; set QEMU_IMAGE_FORMAT" >&2
    exit 1
  fi
  echo "${format}"
}

write_seed_iso() {
  local seed_dir="${1}"
  local seed_iso="${2}"
  local public_key="${3}"

  mkdir -p "${seed_dir}"
  cat >"${seed_dir}/meta-data" <<EOF
instance-id: qemu-boot-smoke-$(date +%s)
local-hostname: qemu-boot-smoke
EOF
  cat >"${seed_dir}/user-data" <<EOF
#cloud-config
ssh_pwauth: false
users:
  - default
  - name: ${QEMU_SSH_USER}
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${public_key}
EOF

  if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds "${seed_iso}" "${seed_dir}/user-data" "${seed_dir}/meta-data"
  elif command -v genisoimage >/dev/null 2>&1; then
    (cd "${seed_dir}" && genisoimage -output "${seed_iso}" -volid cidata -joliet -rock user-data meta-data >/dev/null)
  elif command -v mkisofs >/dev/null 2>&1; then
    (cd "${seed_dir}" && mkisofs -output "${seed_iso}" -volid cidata -joliet -rock user-data meta-data >/dev/null)
  elif command -v xorriso >/dev/null 2>&1; then
    (cd "${seed_dir}" && xorriso -as mkisofs -output "${seed_iso}" -volid cidata -joliet -rock user-data meta-data >/dev/null)
  elif command -v hdiutil >/dev/null 2>&1; then
    hdiutil makehybrid -o "${seed_iso}" -hfs -joliet -iso -default-volume-name cidata "${seed_dir}" >/dev/null
  else
    echo "cloud-localds, genisoimage, mkisofs, xorriso, or hdiutil is required to create the seed ISO" >&2
    exit 1
  fi
}

# shellcheck disable=SC2329 # Called from the EXIT trap.
stop_qemu() {
  local pid="${1:-}"

  if [[ -z "${pid}" ]]; then
    return
  fi
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    return
  fi
  kill "${pid}" >/dev/null 2>&1 || true
  sleep 2
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill -9 "${pid}" >/dev/null 2>&1 || true
  fi
}

require_command "${QEMU_BINARY}"
require_command "${QEMU_IMG}"
require_command ssh

image="$(abs_path "$(resolve_image "${image_arg}")")"
if [[ ! -r "${QEMU_SSH_PRIVATE_KEY}" ]]; then
  echo "SSH private key is not readable: ${QEMU_SSH_PRIVATE_KEY}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/qemu-boot-smoke.XXXXXX")"
qemu_pid=""
# shellcheck disable=SC2329 # Called from the EXIT trap.
cleanup() {
  stop_qemu "${qemu_pid}"
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

ssh_key="${tmp_dir}/ssh_key"
cp "${QEMU_SSH_PRIVATE_KEY}" "${ssh_key}"
chmod 0600 "${ssh_key}"

if [[ -r "${QEMU_SSH_PUBLIC_KEY}" ]]; then
  public_key="$(cat "${QEMU_SSH_PUBLIC_KEY}")"
else
  require_command ssh-keygen
  public_key="$(ssh-keygen -y -f "${ssh_key}")"
fi

backing_format="${QEMU_IMAGE_FORMAT:-$(detect_image_format "${image}")}"
runtime_disk="${tmp_dir}/disk.qcow2"
"${QEMU_IMG}" create -f qcow2 -F "${backing_format}" -b "${image}" "${runtime_disk}" >/dev/null

seed_args=()
case "${QEMU_SEED}" in
cloud-init)
  seed_iso="${tmp_dir}/cidata.iso"
  write_seed_iso "${tmp_dir}/seed" "${seed_iso}" "${public_key}"
  seed_args=(-drive "file=${seed_iso},media=cdrom,readonly=on")
  ;;
none)
  ;;
*)
  echo "unsupported QEMU_SEED=${QEMU_SEED}; expected cloud-init or none" >&2
  exit 1
  ;;
esac

QEMU_ACCELERATOR="${QEMU_ACCELERATOR:-$(detect_accelerator)}"
serial_log="${tmp_dir}/serial.log"
pidfile="${tmp_dir}/qemu.pid"

"${QEMU_BINARY}" \
  -accel "${QEMU_ACCELERATOR}" \
  -machine "${QEMU_MACHINE}" \
  -m "${QEMU_MEMORY}" \
  -smp "${QEMU_CPUS}" \
  -drive "file=${runtime_disk},if=virtio,format=qcow2" \
  "${seed_args[@]}" \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${QEMU_SSH_PORT}-:22" \
  -device "virtio-net-pci,netdev=net0" \
  -display none \
  -serial "file:${serial_log}" \
  -monitor none \
  -no-reboot \
  -pidfile "${pidfile}" \
  -daemonize \
  "${qemu_extra_args[@]}"

qemu_pid="$(cat "${pidfile}")"
deadline=$((SECONDS + QEMU_SSH_TIMEOUT))

echo "Waiting up to ${QEMU_SSH_TIMEOUT}s for SSH on 127.0.0.1:${QEMU_SSH_PORT}..."
while ((SECONDS < deadline)); do
  if ! kill -0 "${qemu_pid}" >/dev/null 2>&1; then
    echo "QEMU exited before SSH became available" >&2
    sed -n '1,160p' "${serial_log}" >&2 || true
    exit 1
  fi

  if ssh \
    -F /dev/null \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o IdentitiesOnly=yes \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${ssh_key}" \
    -p "${QEMU_SSH_PORT}" \
    "${QEMU_SSH_USER}@127.0.0.1" \
    "${QEMU_SMOKE_COMMAND}" >/dev/null; then
    echo "QEMU boot smoke succeeded for ${image}"
    exit 0
  fi

  sleep "${QEMU_SSH_INTERVAL}"
done

echo "Timed out waiting for SSH on 127.0.0.1:${QEMU_SSH_PORT}" >&2
sed -n '1,160p' "${serial_log}" >&2 || true
exit 1
