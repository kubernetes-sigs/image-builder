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

usage() {
  cat >&2 <<'EOF'
Usage: build-sysext-layer.sh --name NAME --version VERSION --rootfs DIR --output-dir DIR --os-id ID --os-version VERSION_ID [--arch ARCH]

Builds an ext4 .raw systemd-sysext image from a rootfs containing only usr/ and opt/.

--os-id and --os-version must match the target host's /usr/lib/os-release
ID and VERSION_ID (for example "ubuntu"/"24.04" or "flatcar"/"4152.2.0"), or
systemd-sysext will refuse to merge the resulting image at runtime.
EOF
}

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

if ! command -v mke2fs >/dev/null 2>&1; then
  echo "mke2fs is required to create ext4 sysext images. Install e2fsprogs." >&2
  exit 1
fi

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

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

cp -a "${rootfs}/." "${workdir}/"
raw_basename="${name}-${version}-${sysext_arch}"
release_dir="${workdir}/usr/lib/extension-release.d"
release_file="${release_dir}/extension-release.${raw_basename}"
mkdir -p "${release_dir}"

if [ ! -f "${release_file}" ]; then
  cat > "${release_file}" <<EOF
ID=${os_id}
VERSION_ID=${os_version}
ARCHITECTURE=${sysext_arch}
SYSEXT_ID=${name}
SYSEXT_VERSION_ID=${version}
EOF
fi

mkdir -p "${output_dir}"
raw="${output_dir}/${raw_basename}.raw"
size_kib="$(du -sk "${workdir}" | awk '{print $1}')"
image_size_kib=$((size_kib + 16384))

rm -f "${raw}"
mke2fs -q -t ext4 -d "${workdir}" "${raw}" "${image_size_kib}K"
echo "${raw}"
