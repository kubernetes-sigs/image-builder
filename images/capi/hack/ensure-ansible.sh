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

_version="2.8.0"

# Change directories to the parent directory of the one in which this
# script is located.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v ansible >/dev/null 2>&1; then exit 0; fi

mkdir -p .bin && cd .bin

if ! command -v python >/dev/null 2>&1; then
  echo "Python binary must be in \$PATH" 1>&2
  exit 1
fi
if ! command -v pip >/dev/null 2>&1; then
  curl -L https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py --user
  rm -f get-pip.py
fi
python -m pip install --user "ansible==${_version}"
if ! command -v ansible >/dev/null 2>&1; then
  echo "User's Python binary directory must bin in \$PATH" 1>&2
  exit 1
fi
