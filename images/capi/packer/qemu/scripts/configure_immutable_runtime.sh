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

FSTAB_PATH="${IMMUTABLE_RUNTIME_FSTAB_PATH:-/etc/fstab}"
RUNTIME_SUDO="${IMMUTABLE_RUNTIME_SUDO-sudo}"
SKIP_MOUNT="${IMMUTABLE_RUNTIME_SKIP_MOUNT:-false}"
SYSTEMD_SYSTEM_DIR="${IMMUTABLE_RUNTIME_SYSTEMD_DIR:-/etc/systemd/system}"
PERSISTENT_MOUNT_PATHS=()
TMPFS_MOUNT_PATHS=()
PERSISTENT_FILES_TO_SYNC=()

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

run_privileged() {
  if [ -n "${RUNTIME_SUDO}" ]; then
    "${RUNTIME_SUDO}" "$@"
  else
    "$@"
  fi
}

path_mode() {
  local path="$1"

  stat -c "%a" "${path}" 2>/dev/null || stat -f "%Lp" "${path}"
}

path_uid() {
  local path="$1"

  stat -c "%u" "${path}" 2>/dev/null || stat -f "%u" "${path}"
}

path_gid() {
  local path="$1"

  stat -c "%g" "${path}" 2>/dev/null || stat -f "%g" "${path}"
}

copy_path_metadata() {
  local path="$1"
  local source="$2"
  local mode
  local uid
  local gid
  local source_uid
  local source_gid

  mode="$(path_mode "${path}")"
  uid="$(path_uid "${path}")"
  gid="$(path_gid "${path}")"
  source_uid="$(path_uid "${source}")"
  source_gid="$(path_gid "${source}")"

  run_privileged chmod "${mode}" "${source}"
  run_privileged touch -r "${path}" "${source}"
  if [ "${uid}:${gid}" != "${source_uid}:${source_gid}" ]; then
    run_privileged chown "${uid}:${gid}" "${source}"
  fi
}

append_or_replace_fstab_entry() {
  local source="$1"
  local target="$2"
  local fstype="$3"
  local options="$4"
  local dump="$5"
  local pass="$6"
  local tmp

  tmp="$(mktemp)"
  awk -v source="${source}" -v target="${target}" '
    $2 == target { next }
    source != "none" && source != "tmpfs" && $1 == source { next }
    { print }
  ' "${FSTAB_PATH}" >"${tmp}"
  printf '%s %s %s %s %s %s\n' "${source}" "${target}" "${fstype}" "${options}" "${dump}" "${pass}" >>"${tmp}"
  run_privileged install -m 0644 "${tmp}" "${FSTAB_PATH}"
  rm -f "${tmp}"
}

validate_absolute_mount_path() {
  local path="$1"
  local variable="$2"

  case "${path}" in
    /*) ;;
    *)
      echo "${variable} entries must be absolute paths: ${path}" >&2
      exit 1
      ;;
  esac
  if [ "${path}" = "/" ]; then
    echo "${variable} must not include /" >&2
    exit 1
  fi
}

for_each_csv_path() {
  local raw="$1"
  local path

  raw="${raw//,/ }"
  for path in ${raw}; do
    [ -n "${path}" ] || continue
    printf '%s\n' "${path}"
  done
}

root_options_with_ro() {
  local current="$1"
  local next=""
  local option
  local -a current_options

  IFS=',' read -ra current_options <<<"${current}"
  for option in "${current_options[@]}"; do
    case "${option}" in
      "" | defaults | rw | ro) ;;
      *) next="${next:+${next},}${option}" ;;
    esac
  done
  printf 'ro%s%s\n' "${next:+,}" "${next}"
}

configure_data_partition() {
  local label="${IMMUTABLE_DATA_PARTITION_LABEL:?}"
  local mount_point="${IMMUTABLE_DATA_PARTITION_MOUNT:?}"
  local fstype="${IMMUTABLE_DATA_PARTITION_FSTYPE:-ext4}"
  local mount_options="${IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS:-defaults,x-systemd.device-timeout=30s}"

  run_privileged install -d -m 0755 "${mount_point}"
  append_or_replace_fstab_entry "LABEL=${label}" "${mount_point}" "${fstype}" "${mount_options}" "0" "2"
  if ! is_true "${SKIP_MOUNT}" && ! mountpoint -q "${mount_point}"; then
    run_privileged mount "${mount_point}"
  fi
}

configure_persistent_path() {
  local path="$1"
  local mount_point="${IMMUTABLE_DATA_PARTITION_MOUNT:?}"
  local persistent_root="${IMMUTABLE_PERSISTENT_PATHS_ROOT:-${mount_point%/}/persistent}"
  local source="${persistent_root}${path}"
  local source_parent

  validate_absolute_mount_path "${path}" "IMMUTABLE_PERSISTENT_PATHS"
  source_parent="$(dirname "${source}")"
  run_privileged install -d -m 0755 "${source_parent}"
  run_privileged install -d -m 0755 "${source}"
  if [ ! -d "${path}" ]; then
    run_privileged install -d -m 0755 "${path}"
  fi
  # Run these probes with the same privilege as the copy below. configure_persistent_path
  # is called for restricted paths like /root (normally mode 0700); an
  # unprivileged `find` on such a path silently returns nothing (its
  # permission error is suppressed by 2>/dev/null), which would make this
  # look empty and skip the copy, hiding the original contents behind an
  # empty bind mount.
  if [ -z "$(run_privileged find "${source}" -mindepth 1 -print -quit 2>/dev/null)" ] &&
    [ -n "$(run_privileged find "${path}" -mindepth 1 -xdev -print -quit 2>/dev/null)" ]; then
    run_privileged cp -a "${path}/." "${source}/"
  fi
  copy_path_metadata "${path}" "${source}"
  append_or_replace_fstab_entry \
    "${source}" \
    "${path}" \
    "none" \
    "bind,x-systemd.requires-mounts-for=${mount_point}" \
    "0" \
    "0"
  PERSISTENT_MOUNT_PATHS+=("${path}")
}

configure_persistent_paths() {
  local paths="${IMMUTABLE_PERSISTENT_PATHS:-}"
  local path

  [ -n "${paths}" ] || return 0
  if ! is_true "${IMMUTABLE_DATA_PARTITION:-false}"; then
    echo "IMMUTABLE_PERSISTENT_PATHS requires IMMUTABLE_DATA_PARTITION=true" >&2
    exit 1
  fi
  while IFS= read -r path; do
    configure_persistent_path "${path}"
  done < <(for_each_csv_path "${paths}")
}

configure_tmpfs_path() {
  local path="$1"
  local mount_options="${IMMUTABLE_TMPFS_MOUNT_OPTIONS:-mode=1777,nosuid,nodev}"

  validate_absolute_mount_path "${path}" "IMMUTABLE_TMPFS_PATHS"
  run_privileged install -d -m 1777 "${path}"
  append_or_replace_fstab_entry "tmpfs" "${path}" "tmpfs" "${mount_options}" "0" "0"
  TMPFS_MOUNT_PATHS+=("${path}")
  if ! is_true "${SKIP_MOUNT}" && ! mountpoint -q "${path}"; then
    run_privileged mount "${path}"
  fi
}

configure_tmpfs_paths() {
  local paths="${IMMUTABLE_TMPFS_PATHS:-}"
  local path

  [ -n "${paths}" ] || return 0
  while IFS= read -r path; do
    configure_tmpfs_path "${path}"
  done < <(for_each_csv_path "${paths}")
}

configure_read_only_root() {
  local source
  local fstype
  local options
  local root_entry

  root_entry="$(awk '$2 == "/" { print $1 "\t" $3 "\t" $4; exit }' "${FSTAB_PATH}")"
  if [ -n "${root_entry}" ]; then
    read -r source fstype options <<<"${root_entry}"
  else
    source="$(findmnt -n -o SOURCE /)"
    fstype="$(findmnt -n -o FSTYPE /)"
    options="defaults"
  fi
  append_or_replace_fstab_entry "${source}" "/" "${fstype}" "$(root_options_with_ro "${options}")" "0" "1"
}

sync_persistent_file_copy() {
  local file="$1"
  local path="$2"
  local mount_point="${IMMUTABLE_DATA_PARTITION_MOUNT:?}"
  local persistent_root="${IMMUTABLE_PERSISTENT_PATHS_ROOT:-${mount_point%/}/persistent}"
  local normalized_path="${path%/}"
  local source
  local relative_file

  [ -n "${normalized_path}" ] || normalized_path="/"
  case "${file}" in
    "${normalized_path}"/*)
      source="${persistent_root}${normalized_path}"
      relative_file="${file#"${normalized_path}/"}"
      run_privileged install -d -m 0755 "$(dirname "${source}/${relative_file}")"
      run_privileged install -m 0644 "${file}" "${source}/${relative_file}"
      ;;
  esac
}

sync_persistent_file_copies() {
  local file
  local path

  PERSISTENT_FILES_TO_SYNC+=("${FSTAB_PATH}")
  for file in ${PERSISTENT_FILES_TO_SYNC[@]+"${PERSISTENT_FILES_TO_SYNC[@]}"}; do
    [ -f "${file}" ] || continue
    for path in ${PERSISTENT_MOUNT_PATHS[@]+"${PERSISTENT_MOUNT_PATHS[@]}"}; do
      sync_persistent_file_copy "${file}" "${path}"
    done
  done
}

requires_mounts_for_paths() {
  local mount_point="${IMMUTABLE_DATA_PARTITION_MOUNT:-}"
  local -a paths=()
  local path

  if is_true "${IMMUTABLE_DATA_PARTITION:-false}" && [ -n "${mount_point}" ]; then
    paths+=("${mount_point}")
  fi
  for path in ${PERSISTENT_MOUNT_PATHS[@]+"${PERSISTENT_MOUNT_PATHS[@]}"}; do
    paths+=("${path}")
  done
  for path in ${TMPFS_MOUNT_PATHS[@]+"${TMPFS_MOUNT_PATHS[@]}"}; do
    paths+=("${path}")
  done
  printf '%s\n' "${paths[@]}" | awk 'NF && !seen[$0]++ { printf "%s%s", sep, $0; sep = " " }'
}

configure_systemd_mount_ordering() {
  local services="${IMMUTABLE_SYSTEMD_MOUNT_ORDERING_SERVICES-cloud-init-local.service,cloud-init.service,cloud-config.service,cloud-final.service,containerd.service,kubelet.service,ssh.service,sshd.service}"
  local mounts
  local service
  local dropin_dir
  local dropin
  local tmp

  [ -n "${services}" ] || return 0
  mounts="$(requires_mounts_for_paths)"
  [ -n "${mounts}" ] || return 0

  while IFS= read -r service; do
    [ -n "${service}" ] || continue
    dropin_dir="${SYSTEMD_SYSTEM_DIR%/}/${service}.d"
    dropin="${dropin_dir}/10-immutable-runtime-mounts.conf"
    tmp="$(mktemp)"
    {
      printf '[Unit]\n'
      printf 'RequiresMountsFor=%s\n' "${mounts}"
    } >"${tmp}"
    run_privileged install -d -m 0755 "${dropin_dir}"
    run_privileged install -m 0644 "${tmp}" "${dropin}"
    rm -f "${tmp}"
    PERSISTENT_FILES_TO_SYNC+=("${dropin}")
  done < <(for_each_csv_path "${services}")
}

mount_persistent_paths() {
  local path

  is_true "${SKIP_MOUNT}" && return 0
  for path in ${PERSISTENT_MOUNT_PATHS[@]+"${PERSISTENT_MOUNT_PATHS[@]}"}; do
    if ! mountpoint -q "${path}"; then
      run_privileged mount "${path}"
    fi
  done
}

if is_true "${IMMUTABLE_DATA_PARTITION:-false}"; then
  configure_data_partition
fi

configure_persistent_paths
configure_tmpfs_paths

if is_true "${IMMUTABLE_READ_ONLY_ROOT:-false}"; then
  configure_read_only_root
fi

configure_systemd_mount_ordering
sync_persistent_file_copies
mount_persistent_paths
