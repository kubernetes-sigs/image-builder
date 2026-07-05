#!/usr/bin/env bash

# Copyright 2024 The Kubernetes Authors.
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

_os=$1
_compute_checksum=$2
_checksum_file=${3:-}
_checksum_search_pattern=${4:-}
_checksum_position=${5:-}

_configs_with_iso_url=()
while IFS= read -r -d '' file; do
    _configs_with_iso_url+=("${file}")
done < <(find packer -type f -name "*${_os}*.json" -print0)

for file in "${_configs_with_iso_url[@]}"; do
    iso_url=$(jq -r ".iso_url // empty" "${file}")
    [[ -n "${iso_url}" ]] || continue

    iso_file_name=$(basename "${iso_url}")
    if [[ "${iso_file_name}" != *.iso ]]; then
        echo "Skipping non-ISO artifact ${iso_url}"
        continue
    fi

    iso_checksum_type=$(jq -r '.iso_checksum_type // "sha256"' "${file}")
    if [[ "${_compute_checksum}" = "true" ]]; then
        iso_checksum=$(curl -SsL "${iso_url}" | "${iso_checksum_type}"sum | awk '{print $1}')
    else
        sha256sums_url="$(dirname "${iso_url}")/${_checksum_file}"
        _checksum_search_pattern=${4/iso_file_name/$iso_file_name}
        iso_checksum=$(curl -SsL "${sha256sums_url}" | grep "${_checksum_search_pattern}" | awk -v col="${_checksum_position}" '{print $col}')
    fi
    tmp=$(mktemp)
    jq --arg iso_checksum "${iso_checksum}" --arg iso_checksum_type "${iso_checksum_type}" '.iso_checksum = $iso_checksum | .iso_checksum_type = $iso_checksum_type' "${file}" > "${tmp}" && mv "${tmp}" "${file}"
done
