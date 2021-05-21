#!/bin/bash

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

################################################################################
# usage: ci-gce.sh
# This program build all images for capi gce
################################################################################

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

CAPI_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
cd "${CAPI_ROOT}" || exit 1

# shellcheck source=ensure-go.sh
source "./hack/ensure-go.sh"
# shellcheck source=ensure-boskosctl.sh
source "./hack/ensure-boskosctl.sh"

# Verify the required Environment Variables are present.
: "${GOOGLE_APPLICATION_CREDENTIALS:?Environment variable empty or not defined.}"

function boskosctlwrapper() {
  boskosctl --server-url http://"${BOSKOS_HOST}" --owner-name "cluster-api-provider-gcp" "${@}"
}

cleanup() {
  echo "Cleaning up image"
  filter="name~cluster-api-ubuntu-*"
  (gcloud compute images list --project "$GCP_PROJECT" \
    --no-standard-images --format="table[no-heading](name)" --filter="${filter}" \
    | awk '{print "gcloud compute images delete --quiet --project '"$GCP_PROJECT"' "$1" " "\n"}' \
    | bash ) || true

  # stop boskos heartbeat
  if [ -n "${BOSKOS_HOST:-}" ]; then
    boskosctlwrapper release --name "${RESOURCE_NAME}" --target-state used
  fi

  exit "${test_status}"
}
trap cleanup EXIT

if [[ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
  cat <<EOF
GOOGLE_APPLICATION_CREDENTIALS is not set.
Please set this to the path of the service account used to run this script.
EOF
  return 2
else
  gcloud auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}"
fi

# If BOSKOS_HOST is set then acquire an GCP account from Boskos.
if [ -n "${BOSKOS_HOST:-}" ]; then
  echo "Boskos acquire - ${BOSKOS_HOST}"
  export BOSKOS_RESOURCE="$( boskosctlwrapper acquire --type gce-project --state free --target-state busy --timeout 1h )"
  export RESOURCE_NAME=$(echo $BOSKOS_RESOURCE | jq  -r ".name")
  export GCP_PROJECT=$(echo $BOSKOS_RESOURCE | jq  -r ".name")

  # send a heartbeat in the background to keep the lease while using the resource
  echo "Starting Boskos HeartBeat"
  boskosctlwrapper heartbeat --resource "${BOSKOS_RESOURCE}" &
fi

# assume we are running in the CI environment as root
# Add a user for ansible to work properly
groupadd -r packer && useradd -m -s /bin/bash -r -g packer packer
chown -R packer:packer /home/prow/go/src/sigs.k8s.io/image-builder
# use the packer user to run the build
su - packer -c "bash -c 'cd /home/prow/go/src/sigs.k8s.io/image-builder/images/capi && PATH=$PATH:~packer/.local/bin:/home/prow/go/src/sigs.k8s.io/image-builder/images/capi/.local/bin GCP_PROJECT_ID=$GCP_PROJECT GOOGLE_APPLICATION_CREDENTIALS=$GOOGLE_APPLICATION_CREDENTIALS PACKER_VAR_FILES=scripts/ci-disable-goss-inspect.json make deps-gce build-gce-all'"
test_status="${?}"

echo "Displaying the generated image information"
filter="name~cluster-api-ubuntu-*"
gcloud compute images list --project "$GCP_PROJECT" --no-standard-images --filter="${filter}"

exit "${test_status}"
