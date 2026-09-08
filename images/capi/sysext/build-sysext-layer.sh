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

set -euo pipefail

# Block headroom added on top of the payload, as a percentage of the payload
# size, with a floor in KiB for small layers. The same percentage is used as the
# margin on the inode count.
SYSEXT_OVERHEAD_PERCENT="${SYSEXT_OVERHEAD_PERCENT:-25}"
SYSEXT_MIN_OVERHEAD_KIB="${SYSEXT_MIN_OVERHEAD_KIB:-16384}"
SYSEXT_MIN_INODES="${SYSEXT_MIN_INODES:-1024}"

usage() {
  cat >&2 <<'EOF'
Usage: build-sysext-layer.sh --name NAME --version VERSION --rootfs DIR --output-dir DIR --os-id ID --os-version VERSION_ID [--arch ARCH]

Builds an ext4 .raw systemd-sysext image from a rootfs containing only usr/ and opt/.

--os-id and --os-version must match the target host's /usr/lib/os-release
ID and VERSION_ID (for example "ubuntu"/"24.04" or "flatcar"/"4152.2.0"), or
systemd-sysext will refuse to merge the resulting image at runtime.

Image contents are always owned by uid 0 and gid 0. That needs either an mke2fs
built with libarchive, so the payload can be handed over as a tar stream with
numeric owner 0, or root privileges so the staging copy can be chowned.
EOF
}

# Sets normalized_int. Called directly rather than in a command substitution so
# that a rejection exits the script instead of only a subshell. Values are
# normalized through base 10 so that a zero-padded number such as 08 is not
# later treated as invalid octal by arithmetic expansion.
normalized_int=0
require_positive_int() {
  local name="$1" value="$2"
  case "${value}" in
    ''|*[!0-9]*)
      echo "${name} must be a positive integer, got: '${value}'" >&2
      exit 2
      ;;
  esac
  normalized_int=$((10#${value}))
  if [ "${normalized_int}" -le 0 ]; then
    echo "${name} must be a positive integer, got: '${value}'" >&2
    exit 2
  fi
}

require_positive_int SYSEXT_OVERHEAD_PERCENT "${SYSEXT_OVERHEAD_PERCENT}"
SYSEXT_OVERHEAD_PERCENT="${normalized_int}"
require_positive_int SYSEXT_MIN_OVERHEAD_KIB "${SYSEXT_MIN_OVERHEAD_KIB}"
SYSEXT_MIN_OVERHEAD_KIB="${normalized_int}"
require_positive_int SYSEXT_MIN_INODES "${SYSEXT_MIN_INODES}"
SYSEXT_MIN_INODES="${normalized_int}"

name=""
version=""
rootfs=""
output_dir=""
os_id=""
os_version=""
arch="$(uname -m)"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --rootfs) rootfs="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --os-id) os_id="$2"; shift 2 ;;
    --os-version) os_version="$2"; shift 2 ;;
    --arch) arch="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "${name}" ] || [ -z "${version}" ] || [ -z "${rootfs}" ] || [ -z "${output_dir}" ] || [ -z "${os_id}" ] || [ -z "${os_version}" ]; then
  echo "--name, --version, --rootfs, --output-dir, --os-id, and --os-version are all required." >&2
  usage
  exit 2
fi

if [ ! -d "${rootfs}" ]; then
  echo "rootfs does not exist: ${rootfs}" >&2
  exit 1
fi

for tool in mke2fs du find awk tar; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "${tool} is required to build sysext images." >&2
    exit 1
  fi
done

case "${arch}" in
  x86_64|amd64) sysext_arch="x86-64" ;;
  aarch64|arm64) sysext_arch="arm64" ;;
  ppc64le) sysext_arch="ppc64-le" ;;
  *) sysext_arch="${arch}" ;;
esac

invalid_paths="$(find "${rootfs}" -mindepth 1 -maxdepth 1 ! -name usr ! -name opt -print)"
if [ -n "${invalid_paths}" ]; then
  echo "systemd-sysext layers may only contain usr/ and opt/ at the root:" >&2
  echo "${invalid_paths}" >&2
  exit 1
fi

workdir=""
cleanup() {
  if [ -n "${workdir}" ]; then
    rm -rf "${workdir}"
    workdir=""
  fi
}
# Cleaning up on signals too, and clearing workdir so the EXIT trap that follows
# a signal is a no-op rather than a second removal.
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

workdir="$(mktemp -d)"

# GNU tar and bsdtar spell the numeric owner override differently. Either way the
# archive records uid 0 and gid 0, so the image does not inherit the build user.
# GNU tar also drops extended attributes unless asked for them, and the default
# include list leaves out the security namespace, which is where file
# capabilities live. bsdtar carries them without being asked.
tar_create_flags=(--owner=0 --group=0 --numeric-owner --xattrs --xattrs-include='*')
tar_extract_flags=(--numeric-owner -p --xattrs --xattrs-include='*')
if tar --version 2>/dev/null | head -n 1 | grep -qi '^bsdtar'; then
  tar_create_flags=(--uid 0 --gid 0 --uname '' --gname '' --numeric-owner)
  tar_extract_flags=(--numeric-owner -p)
fi

# mke2fs only accepts a tarball for -d when it was built with libarchive, which
# is not universal. Probe once with a throwaway image instead of parsing -V.
mke2fs_accepts_tar() {
  local probe="${workdir}/probe"
  mkdir -p "${probe}/src/usr"
  : > "${probe}/src/usr/.probe"
  tar -cf "${probe}/probe.tar" "${tar_create_flags[@]}" -C "${probe}/src" . >/dev/null 2>&1 || return 1
  mke2fs -q -t ext4 -O ^has_journal -d "${probe}/probe.tar" "${probe}/probe.raw" 1024K >/dev/null 2>&1
}

raw_basename="${name}-${version}-${sysext_arch}"
release_path="usr/lib/extension-release.d/extension-release.${raw_basename}"

# Staged separately so the payload never has to be copied just to add one file.
release_overlay=""
if [ ! -f "${rootfs}/${release_path}" ]; then
  release_overlay="${workdir}/release"
  mkdir -p "${release_overlay}/$(dirname "${release_path}")"
  cat > "${release_overlay}/${release_path}" <<EOF
ID=${os_id}
VERSION_ID=${os_version}
ARCHITECTURE=${sysext_arch}
SYSEXT_ID=${name}
SYSEXT_VERSION_ID=${version}
EOF
fi

payload_kib="$(du -sk "${rootfs}" | awk '{print $1}')"
entry_count="$(find "${rootfs}" | wc -l | tr -d '[:space:]')"

# ext4 needs room for inode tables, block group descriptors, and directory
# blocks on top of the payload. A fixed margin is not enough for a payload the
# size of a Kubernetes or containerd release, so scale with the payload and keep
# a floor for tiny layers. The journal is dropped because sysext images are
# mounted read-only.
overhead_kib=$((payload_kib * SYSEXT_OVERHEAD_PERCENT / 100))
if [ "${overhead_kib}" -lt "${SYSEXT_MIN_OVERHEAD_KIB}" ]; then
  overhead_kib="${SYSEXT_MIN_OVERHEAD_KIB}"
fi
image_size_kib=$((payload_kib + overhead_kib))

# mke2fs derives the inode count from the image size at a fixed bytes-per-inode
# ratio, which runs out on payloads made of many small files. Derive it from the
# entry count instead, with the same margin and a floor. The constant covers the
# root directory, lost+found, and the staged extension-release entries.
inode_count=$(((entry_count + 8) * (100 + SYSEXT_OVERHEAD_PERCENT) / 100))
if [ "${inode_count}" -lt "${SYSEXT_MIN_INODES}" ]; then
  inode_count="${SYSEXT_MIN_INODES}"
fi

mke2fs_tar_input=0
if mke2fs_accepts_tar; then
  mke2fs_tar_input=1
fi

if [ "${mke2fs_tar_input}" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  echo "Cannot produce a root-owned sysext image here." >&2
  echo "Install an mke2fs built with libarchive so the payload can be passed as a tar stream, or run this script as root." >&2
  exit 1
fi

mkdir -p "${output_dir}"
raw="${output_dir}/${raw_basename}.raw"
rm -f "${raw}"

# Both paths go through the same archive, so ownership and extended attributes
# are decided in one place. Extracting as root reproduces what mke2fs would have
# read straight from the tar, which chowning a copy would not: chown clears file
# capabilities.
layer_tar="${workdir}/layer.tar"
tar_sources=(-C "${rootfs}" .)
if [ -n "${release_overlay}" ]; then
  tar_sources+=(-C "${release_overlay}" .)
fi
tar -cf "${layer_tar}" "${tar_create_flags[@]}" "${tar_sources[@]}"

# mke2fs up to 1.47.0 announces "Creating regular file <path>" on stdout even
# with -q, so its stdout is kept off this script's stdout, which carries only
# the image path.
if [ "${mke2fs_tar_input}" -eq 1 ]; then
  mke2fs -q -t ext4 -O ^has_journal -N "${inode_count}" -d "${layer_tar}" "${raw}" "${image_size_kib}K" >&2
else
  staging="${workdir}/rootfs"
  mkdir -p "${staging}"
  tar -xf "${layer_tar}" -C "${staging}" "${tar_extract_flags[@]}"
  mke2fs -q -t ext4 -O ^has_journal -N "${inode_count}" -d "${staging}" "${raw}" "${image_size_kib}K" >&2
fi

echo "${raw}"
