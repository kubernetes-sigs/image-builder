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
# usage: ci-gce-nightly.sh
# This program build all images for capi gce for the nightly build
################################################################################

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

CAPI_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
cd "${CAPI_ROOT}" || exit 1

# Verify the required Environment Variables are present.
: "${GCP_PROJECT:?Environment variable empty or not defined.}"

# to list and check if have the properly access to the service account
gcloud auth list

# assume we are running in the CI environment as root
# Add a user for ansible to work properly
groupadd -r packer && useradd -m -s /bin/bash -r -g packer packer
chown -R packer:packer /home/prow/go/src/sigs.k8s.io/image-builder
# use the packer user to run the build

# build image for 1.18
# using PACKER_FLAGS=-force to overwrite the previous image and keep the same name
su - packer -c "bash -c 'cd /home/prow/go/src/sigs.k8s.io/image-builder/images/capi && PATH=$PATH:~packer/.local/bin:/home/prow/go/src/sigs.k8s.io/image-builder/images/capi/.local/bin GCP_PROJECT_ID=$GCP_PROJECT PACKER_VAR_FILES=packer/gce/ci/nightly/overwrite-1-18.json PACKER_FLAGS=-force make deps-gce build-gce-all'"

# build image for 1.19
# using PACKER_FLAGS=-force to overwrite the previous image and keep the same name
su - packer -c "bash -c 'cd /home/prow/go/src/sigs.k8s.io/image-builder/images/capi && PATH=$PATH:~packer/.local/bin:/home/prow/go/src/sigs.k8s.io/image-builder/images/capi/.local/bin GCP_PROJECT_ID=$GCP_PROJECT PACKER_VAR_FILES=packer/gce/ci/nightly/overwrite-1-19.json PACKER_FLAGS=-force make deps-gce build-gce-all'"

# build image for 1.20
# using PACKER_FLAGS=-force to overwrite the previous image and keep the same name
su - packer -c "bash -c 'cd /home/prow/go/src/sigs.k8s.io/image-builder/images/capi && PATH=$PATH:~packer/.local/bin:/home/prow/go/src/sigs.k8s.io/image-builder/images/capi/.local/bin GCP_PROJECT_ID=$GCP_PROJECT PACKER_VAR_FILES=packer/gce/ci/nightly/overwrite-1-20.json PACKER_FLAGS=-force make deps-gce build-gce-all'"

# build image for 1.21
# using PACKER_FLAGS=-force to overwrite the previous image and keep the same name
su - packer -c "bash -c 'cd /home/prow/go/src/sigs.k8s.io/image-builder/images/capi && PATH=$PATH:~packer/.local/bin:/home/prow/go/src/sigs.k8s.io/image-builder/images/capi/.local/bin GCP_PROJECT_ID=$GCP_PROJECT PACKER_VAR_FILES=packer/gce/ci/nightly/overwrite-1-21.json PACKER_FLAGS=-force make deps-gce build-gce-all'"

# build image for 1.22
# using PACKER_FLAGS=-force to overwrite the previous image and keep the same name
su - packer -c "bash -c 'cd /home/prow/go/src/sigs.k8s.io/image-builder/images/capi && PATH=$PATH:~packer/.local/bin:/home/prow/go/src/sigs.k8s.io/image-builder/images/capi/.local/bin GCP_PROJECT_ID=$GCP_PROJECT PACKER_VAR_FILES=packer/gce/ci/nightly/overwrite-1-22.json PACKER_FLAGS=-force make deps-gce build-gce-all'"

echo "Displaying the generated image information"
filter="name~cluster-api-ubuntu-*"
gcloud compute images list --project "$GCP_PROJECT" \
  --no-standard-images --filter="${filter}"

echo "Making images public to use in CI"
(gcloud compute images list --project "$GCP_PROJECT" --no-standard-images --filter="${filter}" --format="value(name[])" | \
awk '{print "gcloud compute images add-iam-policy-binding --project '"$GCP_PROJECT"' " $1 " --member='"'allAuthenticatedUsers'"' --role='"'roles/compute.imageUser'"' \n"}' | bash)
