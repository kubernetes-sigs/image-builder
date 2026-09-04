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

# Shared helpers for booting a built QEMU image on a throwaway copy-on-write
# overlay and driving it over SSH. Sourced by hack/qemu-boot-smoke.sh and
# hack/qemu-node-conformance.sh; it only defines functions.
#
# Callers set the QEMU_GUEST_* globals documented on each function before
# calling it.

qemu_guest_require_command() {
  if ! command -v "${1}" >/dev/null 2>&1; then
    echo "${1} must be in PATH" >&2
    exit 1
  fi
}

qemu_guest_abs_path() {
  local path="${1}"
  local dir
  local base

  dir="$(dirname "${path}")"
  base="$(basename "${path}")"
  echo "$(cd "${dir}" && pwd -P)/${base}"
}

# qemu_guest_resolve_image accepts either a disk image or a Packer output
# directory holding exactly one disk image, and prints the image path. It
# returns non-zero rather than exiting, so that a caller running it in a command
# substitution can act on the failure.
qemu_guest_resolve_image() {
  local input="${1}"
  local matches
  local count

  if [[ -d "${input}" ]]; then
    matches="$(find "${input}" -maxdepth 1 -type f \( -name "*.qcow2" -o -name "*.raw" -o -name "*.img" \) -print | sort)"
    count="$(printf '%s\n' "${matches}" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "${count}" != "1" ]]; then
      echo "expected exactly one *.qcow2, *.raw, or *.img file in ${input}; found ${count}" >&2
      return 1
    fi
    printf '%s\n' "${matches}"
    return 0
  fi

  if [[ ! -f "${input}" ]]; then
    echo "image does not exist: ${input}" >&2
    return 1
  fi

  printf '%s\n' "${input}"
}

# qemu_guest_resolve_image_path prints the absolute path of the image to boot.
#
# Callers must not nest the two steps as
# "$(qemu_guest_abs_path "$(qemu_guest_resolve_image ...)")": the status of an
# inner command substitution is discarded once the outer command runs, so a
# failed resolve would be reported as success with the working directory as the
# image path. Resolving into a variable first keeps the failure observable.
qemu_guest_resolve_image_path() {
  local input="${1}"
  local image

  image="$(qemu_guest_resolve_image "${input}")" || return 1
  if [[ -z "${image}" ]]; then
    echo "could not resolve an image path from: ${input}" >&2
    return 1
  fi

  qemu_guest_abs_path "${image}"
}

qemu_guest_normalize_arch() {
  case "${1}" in
  x86_64 | amd64)
    echo x86_64
    ;;
  aarch64 | arm64)
    echo aarch64
    ;;
  *)
    echo "${1}"
    ;;
  esac
}

qemu_guest_binary_arch() {
  case "$(basename "${1}")" in
  qemu-system-x86_64)
    echo x86_64
    ;;
  qemu-system-aarch64)
    echo aarch64
    ;;
  *)
    echo ""
    ;;
  esac
}

# qemu_guest_detect_accelerator picks a default accelerator for the given QEMU
# binary. hvf and kvm both require the QEMU binary's target architecture to
# match the host architecture; e.g. running qemu-system-x86_64 on an arm64 macOS
# host to boot an amd64 image cannot use hvf and must fall back to tcg.
qemu_guest_detect_accelerator() {
  local qemu_binary="${1}"
  local host_arch
  local binary_arch

  host_arch="$(qemu_guest_normalize_arch "$(uname -m)")"
  binary_arch="$(qemu_guest_binary_arch "${qemu_binary}")"

  case "$(uname -s)" in
  Linux)
    if [[ -z "${binary_arch}" || "${binary_arch}" != "${host_arch}" ]]; then
      echo tcg
    elif [[ -r /dev/kvm && -w /dev/kvm ]]; then
      echo kvm
    else
      echo tcg
    fi
    ;;
  Darwin)
    if [[ -z "${binary_arch}" || "${binary_arch}" != "${host_arch}" ]]; then
      echo tcg
    else
      echo hvf
    fi
    ;;
  *)
    echo tcg
    ;;
  esac
}

# qemu_guest_detect_image_format prints the format of an image. Arguments:
# qemu-img binary, image path.
qemu_guest_detect_image_format() {
  local qemu_img="${1}"
  local image="${2}"
  local format

  qemu_guest_require_command python3
  format="$("${qemu_img}" info --output=json "${image}" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("format", ""))')"
  if [[ -z "${format}" ]]; then
    echo "could not detect image format for ${image}; set QEMU_IMAGE_FORMAT" >&2
    exit 1
  fi
  echo "${format}"
}

# qemu_guest_create_overlay creates a qcow2 copy-on-write overlay so the built
# image is never written to. Arguments: qemu-img binary, backing image, backing
# format, overlay path.
qemu_guest_create_overlay() {
  local qemu_img="${1}"
  local image="${2}"
  local backing_format="${3}"
  local overlay="${4}"

  "${qemu_img}" create -f qcow2 -F "${backing_format}" -b "${image}" "${overlay}" >/dev/null
}

# qemu_guest_write_seed_iso builds a NoCloud seed ISO that creates the SSH user.
# Arguments: seed directory, ISO path, user name, public key, instance name.
qemu_guest_write_seed_iso() {
  local seed_dir="${1}"
  local seed_iso="${2}"
  local user="${3}"
  local public_key="${4}"
  local instance="${5}"

  mkdir -p "${seed_dir}"
  cat >"${seed_dir}/meta-data" <<EOF
instance-id: ${instance}-$(date +%s)
local-hostname: ${instance}
EOF
  cat >"${seed_dir}/user-data" <<EOF
#cloud-config
ssh_pwauth: false
users:
  - default
  - name: ${user}
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

qemu_guest_stop() {
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

# qemu_guest_start boots the guest daemonized and sets QEMU_GUEST_PID.
# Globals: QEMU_GUEST_BINARY, QEMU_GUEST_ACCELERATOR, QEMU_GUEST_MACHINE,
# QEMU_GUEST_MEMORY, QEMU_GUEST_CPUS, QEMU_GUEST_DISK, QEMU_GUEST_SSH_PORT,
# QEMU_GUEST_SERIAL_LOG, QEMU_GUEST_PIDFILE, and the optional arrays
# QEMU_GUEST_SEED_ARGS and QEMU_GUEST_EXTRA_ARGS.
qemu_guest_start() {
  "${QEMU_GUEST_BINARY}" \
    -accel "${QEMU_GUEST_ACCELERATOR}" \
    -machine "${QEMU_GUEST_MACHINE}" \
    -m "${QEMU_GUEST_MEMORY}" \
    -smp "${QEMU_GUEST_CPUS}" \
    -drive "file=${QEMU_GUEST_DISK},if=virtio,format=qcow2" \
    ${QEMU_GUEST_SEED_ARGS[@]+"${QEMU_GUEST_SEED_ARGS[@]}"} \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${QEMU_GUEST_SSH_PORT}-:22" \
    -device "virtio-net-pci,netdev=net0" \
    -display none \
    -serial "file:${QEMU_GUEST_SERIAL_LOG}" \
    -monitor none \
    -no-reboot \
    -pidfile "${QEMU_GUEST_PIDFILE}" \
    -daemonize \
    ${QEMU_GUEST_EXTRA_ARGS[@]+"${QEMU_GUEST_EXTRA_ARGS[@]}"}

  QEMU_GUEST_PID="$(cat "${QEMU_GUEST_PIDFILE}")"
}

# qemu_guest_ssh runs a command in the guest.
# Globals: QEMU_GUEST_SSH_KEY, QEMU_GUEST_SSH_PORT, QEMU_GUEST_SSH_USER.
qemu_guest_ssh() {
  ssh \
    -F /dev/null \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o IdentitiesOnly=yes \
    -o LogLevel=ERROR \
    -o ServerAliveCountMax=20 \
    -o ServerAliveInterval=30 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${QEMU_GUEST_SSH_KEY}" \
    -p "${QEMU_GUEST_SSH_PORT}" \
    "${QEMU_GUEST_SSH_USER}@127.0.0.1" \
    "${@}"
}

# qemu_guest_scp copies files to or from the guest. Remote paths are written as
# guest:/path and are rewritten to the SSH destination.
qemu_guest_scp() {
  local -a args=()
  local arg

  for arg in ${@+"${@}"}; do
    case "${arg}" in
    guest:*)
      args+=("${QEMU_GUEST_SSH_USER}@127.0.0.1:${arg#guest:}")
      ;;
    *)
      args+=("${arg}")
      ;;
    esac
  done

  scp \
    -F /dev/null \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o IdentitiesOnly=yes \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${QEMU_GUEST_SSH_KEY}" \
    -P "${QEMU_GUEST_SSH_PORT}" \
    -r \
    "${args[@]}"
}

# qemu_guest_wait_for_ssh polls the guest until the given probe command
# succeeds over SSH. It fails early if QEMU exits and prints the head of the
# serial log on failure. Arguments: probe command.
# Globals: QEMU_GUEST_PID, QEMU_GUEST_SSH_TIMEOUT, QEMU_GUEST_SSH_INTERVAL,
# QEMU_GUEST_SSH_PORT, QEMU_GUEST_SERIAL_LOG.
qemu_guest_wait_for_ssh() {
  local probe_command="${1}"
  local deadline=$((SECONDS + QEMU_GUEST_SSH_TIMEOUT))

  echo "Waiting up to ${QEMU_GUEST_SSH_TIMEOUT}s for SSH on 127.0.0.1:${QEMU_GUEST_SSH_PORT}..."
  while ((SECONDS < deadline)); do
    if ! kill -0 "${QEMU_GUEST_PID}" >/dev/null 2>&1; then
      echo "QEMU exited before SSH became available" >&2
      qemu_guest_dump_serial_log
      return 1
    fi

    if qemu_guest_ssh "${probe_command}" >/dev/null; then
      return 0
    fi

    sleep "${QEMU_GUEST_SSH_INTERVAL}"
  done

  echo "Timed out waiting for SSH on 127.0.0.1:${QEMU_GUEST_SSH_PORT}" >&2
  qemu_guest_dump_serial_log
  return 1
}

qemu_guest_dump_serial_log() {
  sed -n '1,160p' "${QEMU_GUEST_SERIAL_LOG}" >&2 || true
}
