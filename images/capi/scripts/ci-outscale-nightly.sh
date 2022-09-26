#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

PACKER_VAR_FILES=packer/outscale/ci/nightly/overwrite-1-21.json make build-osc-all
PACKER_VAR_FILES=packer/outscale/ci/nightly/overwrite-1-22.json make build-osc-all
PACKER_VAR_FILES=packer/outscale/ci/nightly/overwrite-1-23.json make build-osc-all
PACKER_VAR_FILES=packer/outscale/ci/nightly/overwrite-1-24.json make build-osc-all
PACKER_VAR_FILES=packer/outscale/ci/nightly/overwrite-1-25.json make build-osc-all
