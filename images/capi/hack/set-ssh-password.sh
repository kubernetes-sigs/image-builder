#!/usr/bin/env bash

# Copyright 2024 The Kubernetes Authors.
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

PACKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../packer" && pwd -P)"

openssl_binary=openssl11
if ! command -v $openssl_binary >/dev/null 2>&1; then
  openssl_binary=openssl
  if ! command -v $openssl_binary >/dev/null 2>&1; then
    echo "openssl or openssl11 binary must be in \$PATH" 1>&2
    exit 1
  fi
fi

# Check if openssl version is atleast 1.1.1 to support SHA-512 algorithm
grep_flags="-Po"
if [[ "$OSTYPE" == "darwin"* ]]; then
  grep_flags="-Eo"
fi
current_openssl_version=$($openssl_binary version | grep $grep_flags "\d.\d.\d" | head -n1)
minimum_openssl_version="1.1.1"
if ! [ "$(printf '%s\n' "$minimum_openssl_version" "$current_openssl_version" | sort -V | head -n1)" = "$minimum_openssl_version" ]; then
  echo "OpenSSL version must be atleast $minimum_openssl_version, current OpenSSL version is $current_openssl_version" 1>&2
  exit 1
fi

export SSH_PASSWORD=${SSH_PASSWORD:-"$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16; echo)"}
SALT=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16; echo)
export ENCRYPTED_SSH_PASSWORD=$($openssl_binary passwd -6 -salt $SALT -stdin <<< $SSH_PASSWORD)

for file in $(find $PACKER_DIR -type f -name "*.tmpl"); do
  if [ -f "${file%.*}" ]; then
    rm ${file%.*}
  fi
  sed -e "s|\$SSH_PASSWORD|$SSH_PASSWORD|g" -e "s|\$ENCRYPTED_SSH_PASSWORD|$ENCRYPTED_SSH_PASSWORD|g" $file | tee ${file%.*}
done
