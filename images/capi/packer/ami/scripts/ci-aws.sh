#!/bin/bash

# Copyright 2019 The Kubernetes Authors.
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
# usage: ci-aws.sh
#  This program builds all the AWS AMIs.
#
# ENVIRONMENT VARIABLES
#  JANITOR_ENABLED
#    Set to 1 to run the aws-janitor command after running the tests.
################################################################################

set -o nounset
set -o pipefail

CAPI_ROOT=$(dirname "${BASH_SOURCE[0]}")/../../..
cd "${CAPI_ROOT}" || exit 1

cleanup() {
  # stop boskos heartbeat
  [[ -z ${HEART_BEAT_PID:-} ]] || kill -9 "${HEART_BEAT_PID}"
}
trap cleanup EXIT

# If BOSKOS_HOST is set then acquire an AWS account from Boskos.
if [ -n "${BOSKOS_HOST:-}" ]; then
  # Check out the account from Boskos and store the produced environment
  # variables in a temporary file.
  account_env_var_file="$(mktemp)"
  python3 ./boskos.py --get 1>"${account_env_var_file}"
  checkout_account_status="${?}"

  # If the checkout process was a success then load the account's
  # environment variables into this process.
  # shellcheck disable=SC1090
  [ "${checkout_account_status}" = "0" ] && . "${account_env_var_file}"

  # Always remove the account environment variable file. It contains
  # sensitive information.
  rm -f "${account_env_var_file}"

  if [ ! "${checkout_account_status}" = "0" ]; then
    echo "error getting account from boskos" 1>&2
    exit "${checkout_account_status}"
  fi

  python3 -u ./boskos.py --hearbeat >>$ARTIFACTS/boskos.log 2>&1 &
  HEART_BEAT_PID=$(echo $!)
fi

export PATH=${PWD}/.local/bin:$PATH
export PATH=${PYTHON_BIN_DIR:-"/root/.local/bin"}:$PATH

# timestamp is in RFC-3339 format to match kubetest
export TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
export JOB_NAME="${JOB_NAME:-"image-builder-ami"}"
export TAGS="creationTimestamp=${TIMESTAMP} jobName=${JOB_NAME}"

make deps-ami
make -j build-ami-all

test_status="${?}"

# If Boskos is being used then release the AWS account back to Boskos.
[ -z "${BOSKOS_HOST:-}" ] || ./boskos.py --release

# The janitor is typically not run as part of the process, but rather
# in a parallel process via a service on the same cluster that runs Prow and
# Boskos.
#
# However, setting JANITOR_ENABLED=1 tells this program to run the janitor
# after the test is executed.
if [ "${JANITOR_ENABLED:-0}" = "1" ]; then
  if ! command -v aws-janitor >/dev/null 2>&1; then
    echo "skipping janitor; aws-janitor not found" 1>&2
  else
    aws-janitor -all -v 2
  fi
else
  echo "skipping janitor; JANITOR_ENABLED=${JANITOR_ENABLED:-0}" 1>&2
fi

exit "${test_status}"
