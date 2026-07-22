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

# Note: ansible-core v2.18 supports Python 3.11-3.13.
_version_ansible_core="2.18.18"

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
*aarch64*)
  HOSTARCH=arm64
  ;;
*arm64*)
  HOSTARCH=arm64
  ;;
*x86_64*)
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

get_shasum() {
  local present_shasum=''
  if command -v shasum >/dev/null 2>&1; then
    present_shasum=$(shasum -a 256 "${1}"| awk -F' ' '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    present_shasum=$(sha256sum "${1}" | awk -F' ' '{print $1}')
  else
    echo "missing shasum tool" 1>&2
    return 1
  fi
  echo "$present_shasum"
}

ensure_py3_bin() {
  # If given executable is not available, the user Python bin dir is not in path
  # This function assumes the executable to be checked was installed with
  # pip3 install --user ...
  if ! command -v "${1}" >/dev/null 2>&1; then
    echo "User's Python3 binary directory must be in \$PATH" 1>&2
    echo "Location of package is:" 1>&2
    pip3 show --disable-pip-version-check "${2:-$1}" | grep "Location"
    echo "\$PATH is currently: $PATH" 1>&2
    exit 1
  fi
}

ensure_py3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 binary must be in \$PATH" 1>&2
    exit 1
  fi
  if ! command -v pip3 >/dev/null 2>&1; then
    curl -SsL https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python3 get-pip.py --user
    rm -f get-pip.py
    ensure_py3_bin pip3
  fi
}

pip3_install() {
  ensure_py3
  if output=$(pip3 install --disable-pip-version-check --user "${@}" 2>&1); then
    echo "$output"
  elif [[ $output == *"Can not perform a '--user' install"* ]]; then
    >&2 echo "warning: '--user' install failed, retrying pip3 install without --user"
    pip3 install --disable-pip-version-check "${@}"
  elif [[ $output == *"error: externally-managed-environment"* ]]; then
    >&2 echo "warning: externally-managed-environment, retrying pip3 install with --break-system-packages"
    pip3 install --disable-pip-version-check --user --break-system-packages "${@}"
  else
    >&2 echo "$output"
    exit 1
  fi
}

ansible_galaxy_collection_install() {
  local -a galaxy_args=()
  local xtrace_was_on=false
  [[ $- == *x* ]] && xtrace_was_on=true

  if [[ -n "${ANSIBLE_GALAXY_SERVER:-}" ]]; then
    galaxy_args+=(--server "${ANSIBLE_GALAXY_SERVER}")
  fi

  # Never let xtrace print the Galaxy token: disable it before even checking
  # ANSIBLE_GALAXY_TOKEN (xtrace would otherwise echo the expanded value of
  # that condition) and restore whatever xtrace state was active before.
  set +o xtrace
  if [[ -n "${ANSIBLE_GALAXY_TOKEN:-}" ]]; then
    galaxy_args+=(--token "${ANSIBLE_GALAXY_TOKEN}")
  fi
  [[ "${xtrace_was_on}" == true ]] && set -o xtrace

  if [[ "${ANSIBLE_GALAXY_IGNORE_CERTS:-false}" == "true" ]]; then
    galaxy_args+=(--ignore-certs)
  fi
  if [[ -n "${ANSIBLE_GALAXY_TIMEOUT:-}" ]]; then
    galaxy_args+=(--timeout "${ANSIBLE_GALAXY_TIMEOUT}")
  fi
  if [[ -n "${ANSIBLE_GALAXY_COLLECTIONS_PATH:-}" ]]; then
    galaxy_args+=(--collections-path "${ANSIBLE_GALAXY_COLLECTIONS_PATH}")
    # ansible-galaxy only reads ANSIBLE_GALAXY_COLLECTIONS_PATH for the
    # install itself. Ansible discovers collections at runtime via the
    # standard ANSIBLE_COLLECTIONS_PATH variable, and most provisioner
    # templates never forward a custom path otherwise, so export it here
    # too to make the installed collections actually usable later.
    export ANSIBLE_COLLECTIONS_PATH="${ANSIBLE_GALAXY_COLLECTIONS_PATH}"
  fi
  if [[ "${ANSIBLE_GALAXY_NO_CACHE:-false}" == "true" ]]; then
    galaxy_args+=(--no-cache)
  fi
  if [[ "${ANSIBLE_GALAXY_OFFLINE:-false}" == "true" ]]; then
    galaxy_args+=(--offline)
  fi

  # Suspend xtrace again for the final command: galaxy_args may contain the
  # token added above, and it would otherwise be written to the trace log.
  set +o xtrace
  local rc
  ansible-galaxy collection install ${galaxy_args[@]+"${galaxy_args[@]}"} "$@"
  rc=$?
  [[ "${xtrace_was_on}" == true ]] && set -o xtrace
  return "${rc}"
}

hostarch_without_darwin_arm64() {
  if [ "${HOSTOS}" == "darwin" ] && [ "${HOSTARCH}" == "arm64" ]; then
    echo "amd64"
  else
    echo ${HOSTARCH}
  fi
}
