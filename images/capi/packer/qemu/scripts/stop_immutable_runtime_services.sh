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

# Stops the container runtime services before configure_immutable_runtime.sh
# copies /var/lib (and other persistent paths) onto the data partition and
# bind-mounts them back into place. Both units are installed on every QEMU
# Ubuntu variant, but only some of them enable the immutable target; on the
# variants where the immutable target is disabled this script is a no-op.
#
# A genuine `systemctl stop` failure (e.g. the unit hung, or dependency
# ordering broke) must fail the build: copying live container/kubelet state
# into the persistent store would otherwise corrupt the runtime data. Only an
# absent unit is tolerated, since some qemu-ubuntu variants may not install
# both services.

set -o errexit
set -o nounset
set -o pipefail

IMMUTABLE_DATA_PARTITION="${IMMUTABLE_DATA_PARTITION:-false}"
IMMUTABLE_READ_ONLY_ROOT="${IMMUTABLE_READ_ONLY_ROOT:-false}"
IMMUTABLE_PERSISTENT_PATHS="${IMMUTABLE_PERSISTENT_PATHS:-}"

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

unit_exists() {
  local service="$1"

  [ -n "$(systemctl list-unit-files "${service}" --no-legend 2>/dev/null)" ]
}

stop_service_if_present() {
  local service="$1"

  if ! unit_exists "${service}"; then
    echo "Skipping stop for ${service}: unit not found" >&2
    return 0
  fi
  systemctl stop "${service}"
}

if is_true "${IMMUTABLE_DATA_PARTITION}" ||
  is_true "${IMMUTABLE_READ_ONLY_ROOT}" ||
  [ -n "${IMMUTABLE_PERSISTENT_PATHS}" ]; then
  stop_service_if_present kubelet.service
  stop_service_if_present containerd.service
fi
