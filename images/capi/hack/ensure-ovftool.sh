#!/usr/bin/env bash

# Copyright 2021 The Kubernetes Authors.
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

[[ -n ${DEBUG:-} ]] && set -o xtrace

[[ -z ${IB_OVFTOOL:-} ]] && exit 0

source hack/utils.sh

if command -v ovftool >/dev/null 2>&1; then exit 0; fi

echo "ovftool must be present to build OVAs. If already installed" >&2
echo "make sure to add it to the PATH env var. If not installed, please" >&2
echo "install latest from https://code.vmware.com/tool/ovf." >&2
exit 1
