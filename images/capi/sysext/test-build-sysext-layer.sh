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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for tool in mke2fs debugfs; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "SKIP: ${tool} is required for sysext layer helper smoke test" >&2
    exit 0
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  if [ -n "${workdir}" ]; then
    rm -rf "${workdir}"
    workdir=""
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# The helper refuses to build unless it can force uid/gid 0, which needs either
# an mke2fs built with libarchive or root. Skip instead of failing elsewhere.
# Sets build_layer_raw. Not a command substitution at the call site, so a skip
# can exit the script rather than just the subshell.
build_layer_raw=""
build_layer() {
  local stderr_file="${workdir}/build.err" status=0
  build_layer_raw="$("${script_dir}/build-sysext-layer.sh" "$@" 2>"${stderr_file}")" || status=$?
  if [ "${status}" -ne 0 ]; then
    if grep -q "Cannot produce a root-owned sysext image here" "${stderr_file}"; then
      echo "SKIP: this host can neither pass a tar stream to mke2fs nor run as root" >&2
      exit 0
    fi
    cat "${stderr_file}" >&2
    exit "${status}"
  fi
}

# debugfs exits 0 whether or not the path resolves, so check that it actually
# printed an inode, and that the inode is owned by root.
assert_root_owned_file_in_image() {
  local image="$1" path="$2" stat_out
  stat_out="$(debugfs -R "stat ${path}" "${image}" 2>/dev/null)"
  if ! printf '%s' "${stat_out}" | grep -q '^Inode:'; then
    echo "missing expected path in sysext image: ${path}" >&2
    exit 1
  fi
  if ! printf '%s' "${stat_out}" | grep -qE '^User: +0 +Group: +0'; then
    echo "expected ${path} to be owned by uid 0 / gid 0, got:" >&2
    printf '%s' "${stat_out}" | grep -E '^User:' >&2
    exit 1
  fi
}

# Payloads are given a non-root owner so that the ownership assertions below
# still mean something when this runs as root, where every file would otherwise
# be uid 0 before the helper does anything.
stage_payload_owner() {
  if [ "$(id -u)" -eq 0 ]; then
    chown -R 65534:65534 "$1"
  fi
}

# Layer with a regular payload file.
rootfs="${workdir}/rootfs"
mkdir -p "${rootfs}/usr/share/sysext-test"
printf 'ok\n' > "${rootfs}/usr/share/sysext-test/payload"
stage_payload_owner "${rootfs}"

build_layer \
  --name sysext-test \
  --version v1.2.3 \
  --rootfs "${rootfs}" \
  --output-dir "${workdir}/out" \
  --os-id ubuntu \
  --os-version 24.04 \
  --arch x86_64
raw="${build_layer_raw}"

assert_root_owned_file_in_image "${raw}" \
  "/usr/lib/extension-release.d/extension-release.sysext-test-v1.2.3-x86-64"
assert_root_owned_file_in_image "${raw}" "/usr/share/sysext-test/payload"

image_inode_count() {
  debugfs -R stats "$1" 2>/dev/null | awk -F': *' '/^Inode count:/ {print $2; exit}'
}

# Layer made of many files, to exercise a multi-entry payload end to end.
many_rootfs="${workdir}/many"
mkdir -p "${many_rootfs}/usr/share/sysext-many"
for i in $(seq 1 1000); do
  printf 'x' > "${many_rootfs}/usr/share/sysext-many/f${i}"
done
stage_payload_owner "${many_rootfs}"

build_layer \
  --name sysext-many \
  --version v1 \
  --rootfs "${many_rootfs}" \
  --output-dir "${workdir}/out" \
  --os-id ubuntu \
  --os-version 24.04 \
  --arch x86_64
many_raw="${build_layer_raw}"

assert_root_owned_file_in_image "${many_raw}" "/usr/share/sysext-many/f1000"

many_inodes="$(image_inode_count "${many_raw}")"
if [ -z "${many_inodes}" ] || [ "${many_inodes}" -lt 1000 ]; then
  echo "expected the many-file image to hold at least 1000 inodes, got: '${many_inodes}'" >&2
  exit 1
fi

# mke2fs derives the inode count from the image size unless it is told
# otherwise, and that default runs out on payloads made of many small files.
# Ask for far more inodes than the default would give for an image this size,
# so this fails if the helper stops passing -N.
inode_floor=12000
export SYSEXT_MIN_INODES="${inode_floor}"
build_layer \
  --name sysext-inodes \
  --version v1 \
  --rootfs "${rootfs}" \
  --output-dir "${workdir}/out" \
  --os-id ubuntu \
  --os-version 24.04 \
  --arch x86_64
inode_raw="${build_layer_raw}"
unset SYSEXT_MIN_INODES

forced_inodes="$(image_inode_count "${inode_raw}")"
if [ -z "${forced_inodes}" ] || [ "${forced_inodes}" -lt "${inode_floor}" ]; then
  echo "expected the image to be sized for at least ${inode_floor} inodes, got: '${forced_inodes}'" >&2
  echo "the helper is not passing -N to mke2fs" >&2
  exit 1
fi

echo "sysext layer helper smoke test passed"
