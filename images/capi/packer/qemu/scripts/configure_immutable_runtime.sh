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

is_true() {
  case "${1,,}" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
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
  sudo awk -v source="${source}" -v target="${target}" '
    $1 == source || $2 == target { next }
    { print }
  ' /etc/fstab >"${tmp}"
  printf '%s %s %s %s %s %s\n' "${source}" "${target}" "${fstype}" "${options}" "${dump}" "${pass}" >>"${tmp}"
  sudo install -m 0644 "${tmp}" /etc/fstab
  rm -f "${tmp}"
}

root_options_with_ro() {
  local current="$1"
  local next=""
  local option

  IFS=',' read -ra options <<<"${current}"
  for option in "${options[@]}"; do
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
  local options="${IMMUTABLE_DATA_PARTITION_MOUNT_OPTIONS:-defaults,nofail}"

  sudo install -d -m 0755 "${mount_point}"
  append_or_replace_fstab_entry "LABEL=${label}" "${mount_point}" "${fstype}" "${options}" "0" "2"
  if ! mountpoint -q "${mount_point}"; then
    sudo mount "${mount_point}"
  fi
}

configure_read_only_root() {
  local source
  local fstype
  local options
  local root_entry

  root_entry="$(awk '$2 == "/" { print $1 "\t" $3 "\t" $4; exit }' /etc/fstab)"
  if [ -n "${root_entry}" ]; then
    read -r source fstype options <<<"${root_entry}"
  else
    source="$(findmnt -n -o SOURCE /)"
    fstype="$(findmnt -n -o FSTYPE /)"
    options="defaults"
  fi
  append_or_replace_fstab_entry "${source}" "/" "${fstype}" "$(root_options_with_ro "${options}")" "0" "1"
}

if is_true "${IMMUTABLE_DATA_PARTITION:-false}"; then
  configure_data_partition
fi

if is_true "${IMMUTABLE_READ_ONLY_ROOT:-false}"; then
  configure_read_only_root
fi
