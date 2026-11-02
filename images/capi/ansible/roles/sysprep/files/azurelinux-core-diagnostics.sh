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

# Temporary metadata-only tracing for the Azure Linux 3 CI failure.
set -o errexit
set -o nounset
set -o pipefail

phase="${1:?A diagnostic phase is required}"
shift
if [[ "${AZURELINUX_CORE_DIAGNOSTICS:-true}" != "true" ]]; then
  printf 'Skipping temporary Azure Linux 3 core diagnostics for this image.\n'
  exit 0
fi
if [[ $# -eq 0 ]]; then
  set -- /var/crash /var/lib/systemd/coredump /var/tmp /tmp
fi

find_core_candidates() {
  local root="$1"
  shift
  find "${root}" -xdev -type f \
    \( -name core -o -name "core.*" -o -name "*.core" \) "$@"
}

status=0
printf 'AZURE-LINUX-CORE-DIAGNOSTICS phase=%s time=%s\n' \
  "${phase}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

for root in "$@"; do
  printf 'CORE-DIRECTORY %s\n' "${root}"
  if [[ ! -d "${root}" ]]; then
    printf 'Directory is absent; nothing to inspect.\n'
    continue
  fi
  find_core_candidates "${root}" -print -exec ls -ln -- '{}' + || status=$?
  if command -v file >/dev/null 2>&1; then
    find_core_candidates "${root}" -exec file --mime-type -- '{}' + || status=$?
  else
    printf 'file utility is unavailable; MIME types were not collected.\n'
  fi
done

# Do not print MESSAGE, command lines, environment variables, or core contents.
printf 'CORE-JOURNAL metadata only\n'
if command -v journalctl >/dev/null 2>&1; then
  journalctl --no-pager --output=json -t systemd-coredump \
    --output-fields=COREDUMP_COMM,COREDUMP_EXE,COREDUMP_FILENAME,COREDUMP_SIGNAL,COREDUMP_TIMESTAMP \
    || status=$?
else
  printf 'journalctl is unavailable; crash journal metadata was not collected.\n' >&2
  status=1
fi

exit "${status}"
