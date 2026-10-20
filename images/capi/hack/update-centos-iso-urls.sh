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

# Repoints CentOS Stream iso_url values at the newest compose published on the
# mirror.
#
# CentOS Stream keeps only the most recent compose in the BaseOS iso directory
# and prunes older ones, so a dated iso_url stops resolving after a few weeks
# and update-iso-checksums.sh can no longer find its entry in SHA256SUM. This
# resolves the current dated compose from SHA256SUM and rewrites iso_url before
# the checksum refresh runs.
#
# The dated name is used rather than the CentOS-Stream-N-latest-* symlink so the
# pinned URL keeps naming one specific compose that the checksum belongs to.
#
# Usage: hack/update-centos-iso-urls.sh <os>
#   e.g. hack/update-centos-iso-urls.sh centos-9

set -o errexit
set -o nounset
set -o pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <os>" >&2
    exit 1
fi

_os=$1

_tmp=""
trap 'rm -f "${_tmp}"' EXIT

for file in packer/*/*"${_os}"*.json; do
    [ -f "${file}" ] || continue

    iso_url=$(jq -r '.iso_url // empty' "${file}")
    [ -n "${iso_url}" ] || continue

    # Both dated and -latest- CentOS Stream DVD pins are rewritten to the newest
    # dated compose; anything else is left alone.
    case "${iso_url}" in
        https://mirror.stream.centos.org/*-stream/BaseOS/x86_64/iso/CentOS-Stream-*-x86_64-dvd1.iso) ;;
        *)
            echo "${file}: iso_url is not a mirror.stream.centos.org CentOS Stream pin, skipping"
            continue
            ;;
    esac

    stream=$(echo "${iso_url}" | sed -n 's#^https://mirror\.stream\.centos\.org/\([0-9][0-9]*\)-stream/.*#\1#p')
    if [ -z "${stream}" ]; then
        echo "ERROR: ${file}: cannot determine CentOS Stream version from ${iso_url}" >&2
        exit 1
    fi

    iso_dir=$(dirname "${iso_url}")
    current_iso=$(basename "${iso_url}")

    if ! sums=$(curl -fSsL "${iso_dir}/SHA256SUM"); then
        echo "ERROR: ${file}: cannot fetch ${iso_dir}/SHA256SUM" >&2
        exit 1
    fi

    # Dated composes only: the 8 digit date excludes the -latest- symlink names.
    # Version sort so a .10 respin ranks above .9 on the same date.
    latest_iso=$(echo "${sums}" \
        | grep -oE "CentOS-Stream-${stream}-[0-9]{8}\.[0-9]+-x86_64-dvd1\.iso" \
        | sort -V -u \
        | tail -n 1) || true

    if [ -z "${latest_iso}" ]; then
        echo "ERROR: ${file}: no dated CentOS Stream ${stream} compose listed in ${iso_dir}/SHA256SUM" >&2
        exit 1
    fi

    if [ "${latest_iso}" = "${current_iso}" ]; then
        echo "${file}: already at ${current_iso}"
        continue
    fi

    _tmp=$(mktemp)
    jq --arg iso_url "${iso_dir}/${latest_iso}" '.iso_url = $iso_url' "${file}" > "${_tmp}"
    mv "${_tmp}" "${file}"
    echo "${file}: ${current_iso} -> ${latest_iso}"
done
