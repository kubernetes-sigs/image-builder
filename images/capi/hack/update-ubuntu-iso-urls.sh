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

cache_dir="$(mktemp -d)"
trap 'rm -rf "${cache_dir}"' EXIT

find_latest_iso() {
    local series=$1
    local arch=$2
    local checksum_url=$3
    local url_style=$4
    local cache_key="${series}-${arch}-${url_style}"
    local checksum_data
    local checksum_data_file
    local http_status
    local latest_entry
    local latest_version

    if [[ -s "${cache_dir}/${cache_key}.file" ]]; then
        latest_iso_file="$(cat "${cache_dir}/${cache_key}.file")"
        latest_iso_checksum="$(cat "${cache_dir}/${cache_key}.checksum")"
        latest_iso_url="$(cat "${cache_dir}/${cache_key}.url")"
        return 0
    fi

    if [[ -e "${cache_dir}/${cache_key}.skip" ]]; then
        return 1
    fi

    checksum_data_file="${cache_dir}/${cache_key}.raw"
    if ! http_status="$(curl -sSL -o "${checksum_data_file}" -w '%{http_code}' "${checksum_url}")"; then
        echo "ERROR: network error fetching ${checksum_url}" >&2
        exit 1
    fi

    if [[ "${http_status}" == "404" ]]; then
        echo "WARNING: ${checksum_url} returned 404; Ubuntu ${series} has no point release yet; skipping ${arch}" >&2
        touch "${cache_dir}/${cache_key}.skip"
        return 1
    fi

    if [[ "${http_status}" != "200" ]]; then
        echo "ERROR: ${checksum_url} returned HTTP ${http_status}" >&2
        exit 1
    fi

    checksum_data="$(cat "${checksum_data_file}")"

    latest_entry="$(
        printf '%s\n' "${checksum_data}" |
            awk -v series="${series}" -v arch="${arch}" '
                $2 ~ "\\*ubuntu-" series "\\.[0-9]+-live-server-" arch "\\.iso$" {
                    print $1, substr($2, 2)
                }
            ' |
            sort -k2,2V |
            tail -n1
    )"

    if [[ -z "${latest_entry}" ]]; then
        echo "WARNING: ${checksum_url} has no point-release live-server ISO for Ubuntu ${series} ${arch}" >&2
        touch "${cache_dir}/${cache_key}.skip"
        return 1
    fi

    latest_iso_file="${latest_entry#* }"
    latest_iso_checksum="${latest_entry%% *}"
    latest_version="${latest_iso_file#ubuntu-}"
    latest_version="${latest_version%-live-server-"${arch}".iso}"

    case "${url_style}" in
        releases)
            latest_iso_url="https://releases.ubuntu.com/${latest_version}/${latest_iso_file}"
            ;;
        cdimage)
            latest_iso_url="https://cdimage.ubuntu.com/releases/${latest_version}/release/${latest_iso_file}"
            ;;
        *)
            echo "ERROR: unsupported Ubuntu ISO URL style: ${url_style}" >&2
            return 1
            ;;
    esac

    printf '%s\n' "${latest_iso_file}" > "${cache_dir}/${cache_key}.file"
    printf '%s\n' "${latest_iso_checksum}" > "${cache_dir}/${cache_key}.checksum"
    printf '%s\n' "${latest_iso_url}" > "${cache_dir}/${cache_key}.url"
}

while IFS= read -r -d '' file; do
    iso_url="$(jq -r '.iso_url // empty' "${file}")"
    [[ -n "${iso_url}" ]] || continue

    iso_file_name="$(basename "${iso_url}")"
    if [[ ! "${iso_file_name}" =~ ^ubuntu-([0-9]{2}\.[0-9]{2})(\.[0-9]+)?-live-server-(amd64|arm64)\.iso$ ]]; then
        continue
    fi

    series="${BASH_REMATCH[1]}"
    arch="${BASH_REMATCH[3]}"
    case "${iso_url}" in
        https://releases.ubuntu.com/*)
            checksum_url="https://releases.ubuntu.com/${series}/SHA256SUMS"
            url_style="releases"
            ;;
        https://cdimage.ubuntu.com/releases/*)
            checksum_url="https://cdimage.ubuntu.com/releases/${series}/release/SHA256SUMS"
            url_style="cdimage"
            ;;
        *)
            continue
            ;;
    esac

    find_latest_iso "${series}" "${arch}" "${checksum_url}" "${url_style}" || continue

    current_checksum="$(jq -r '.iso_checksum // empty' "${file}")"
    if [[ "${iso_url}" == "${latest_iso_url}" && "${current_checksum}" == "${latest_iso_checksum}" ]]; then
        continue
    fi

    tmp="$(mktemp)"
    jq \
        --arg iso_url "${latest_iso_url}" \
        --arg iso_checksum "${latest_iso_checksum}" \
        --arg iso_file "${latest_iso_file}" \
        '
          .iso_url = $iso_url
          | .iso_checksum = $iso_checksum
          | .iso_checksum_type = (.iso_checksum_type // "sha256")
          | if (.iso_target_path? | type) == "string" then
              .iso_target_path |= sub("ubuntu-[0-9]+\\.[0-9]+(\\.[0-9]+)?-live-server-(amd64|arm64)\\.iso$"; $iso_file)
            else
              .
            end
        ' "${file}" > "${tmp}"
    mv "${tmp}" "${file}"

    echo "Updated ${file} to ${latest_iso_file}"
done < <(find packer -type f -name '*ubuntu*.json' -print0)
