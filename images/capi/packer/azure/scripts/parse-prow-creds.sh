#!/bin/bash
# Copyright 2020 The Kubernetes Authors.
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
set +o xtrace

parse_cred() {
    grep -E -o "\b$1[[:blank:]]*=[[:blank:]]*\"[^[:space:]\"]+\"" | cut -d '"' -f 2
}


# for Prow we use the provided AZURE_CREDENTIALS file.
# the file is expected to be in toml format.
if [[ -n "${AZURE_CREDENTIALS:-}" ]]; then
    export AZURE_SUBSCRIPTION_ID="$(cat ${AZURE_CREDENTIALS} | parse_cred SubscriptionID)"
    export AZURE_TENANT_ID="$(cat ${AZURE_CREDENTIALS} | parse_cred TenantID)"
    export AZURE_CLIENT_ID="$(cat ${AZURE_CREDENTIALS} | parse_cred ClientID)"
    export AZURE_CLIENT_SECRET="$(cat ${AZURE_CREDENTIALS} | parse_cred ClientSecret)"
fi
