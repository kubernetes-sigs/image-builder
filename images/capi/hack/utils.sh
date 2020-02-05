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

case "${OSTYPE}" in
linux*)
  HOSTOS=linux
  ;;
darwin*)
  HOSTOS=darwin
  ;;
*)
  echo "unsupported HOSTOS=${OSTYPE}" 1>&2
  exit 1
  ;;
esac

_hostarch=$(uname -m)
case "${_hostarch}" in
*64*)
  HOSTARCH=amd64
  ;;
*386*)
  HOSTARCH=386
  ;;
*686*)
  HOSTARCH=386
  ;;
*)
  echo "unsupported HOSTARCH=${_hostarch}" 1>&2
  exit 1
  ;;
esac

checksum_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c "${1}"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "${1}"
  else
    echo "missing shasum tool" 1>&2
    return 1
  fi
}
