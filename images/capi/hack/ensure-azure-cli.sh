#!/usr/bin/env bash

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

_version="2.9.0"

# Change directories to the parent directory of the one in which this
# script is located.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v az >/dev/null 2>&1; then exit 0; fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 binary must be in \$PATH" 1>&2
  exit 1
fi

if ! command -v pip3 >/dev/null 2>&1; then
  curl -SsL https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python3 get-pip.py --user
  rm -f get-pip.py
fi

pip3 install --user "azure-cli==${_version}"

if ! command -v azure-cli >/dev/null 2>&1; then
  echo "User's Python3 binary directory must bin in \$PATH" 1>&2
  exit 1
fi
