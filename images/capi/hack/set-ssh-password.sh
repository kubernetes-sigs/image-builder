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
ENCRYPTED_SSH_PASSWORD=$($openssl_binary passwd -6 -salt "$SALT" -stdin <<< "$SSH_PASSWORD")
export ENCRYPTED_SSH_PASSWORD

# The values are injected with sed, so every character that is special in a sed
# replacement has to be escaped first: a backslash, an ampersand (the whole
# match) and the "|" delimiter. A newline cannot be escaped this way, so reject
# it instead of silently producing a broken template.
if [[ "$SSH_PASSWORD" == *$'\n'* ]]; then
  echo "SSH_PASSWORD must not contain a newline" 1>&2
  exit 1
fi

# escape_sed_replacement prints its argument escaped for use as the replacement
# text of a "s|...|...|" expression.
escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[|&\\]/\\&/g'
}

escaped_ssh_password=$(escape_sed_replacement "$SSH_PASSWORD")
escaped_encrypted_ssh_password=$(escape_sed_replacement "$ENCRYPTED_SSH_PASSWORD")

# The rendered files are written with a redirect rather than piped through tee:
# they contain the plaintext password, the password hash and whatever other
# credentials a template carries, and tee would copy all of it into the build
# log. Only the path of each rendered file is printed.
find "$PACKER_DIR" -type f -name "*.tmpl" -print0 | while IFS= read -r -d '' file; do
  rendered=${file%.*}
  if [ -f "$rendered" ]; then
    # HACK: There seems to be a case where this can actually
    # fail with the file not being found, leading to test failures.
    # If we fail to remove the file we just continue and assume
    # that the file was already removed.
    rm "$rendered" || true
  fi
  sed -e "s|\$SSH_PASSWORD|$escaped_ssh_password|g" \
      -e "s|\$ENCRYPTED_SSH_PASSWORD|$escaped_encrypted_ssh_password|g" \
      "$file" > "$rendered"
  echo "rendered $rendered"
done
