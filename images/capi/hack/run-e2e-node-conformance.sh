#!/usr/bin/env bash

# Copyright 2026 The Kubernetes Authors.
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

# Guest-side Kubernetes node conformance hook.
#
# This script is not run during an image build. hack/qemu-node-conformance.sh
# boots the already built image from a throwaway qcow2 overlay, copies this
# script in, runs it, and copies ${NODE_CONFORMANCE_RESULTS_DIR} back out before
# discarding the overlay. Everything it writes is therefore confined to a disk
# that is deleted afterwards, and the shipped image is only ever read from.

set -euo pipefail

log() {
  printf '[node-conformance] %s\n' "$*" >&2
}

die() {
  printf '[node-conformance] ERROR: %s\n' "$*" >&2
  exit 1
}

is_true() {
  local value="${1:-false}"

  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
  case "${value}" in
    true | 1 | yes) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

detect_go_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

normalize_kubernetes_version() {
  local version="$1"
  version="${version#v}"
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "KUBERNETES_VERSION must look like 1.36.2 or v1.36.2"
  printf '%s\n' "${version}"
}

# detect_kubernetes_version reads the version out of the image under test so the
# downloaded test tarball always matches the kubelet that is being validated.
detect_kubernetes_version() {
  local version

  command -v kubelet >/dev/null 2>&1 ||
    die "KUBERNETES_VERSION is unset and kubelet is not installed in this image"
  version="$(kubelet --version 2>/dev/null | awk '{print $2}')"
  [[ -n "${version}" ]] || die "could not read the Kubernetes version from kubelet"
  printf '%s\n' "${version}"
}

verify_sha256_file() {
  local file="$1"
  local sha_file="$2"
  local expected=""

  # dl.k8s.io serves the checksum without a trailing newline, so read reports
  # EOF even though it assigned the digest. Validate the value it read rather
  # than its exit status.
  read -r expected _ <"${sha_file}" || true
  [[ "${expected}" =~ ^[A-Fa-f0-9]{64}$ ]] ||
    die "invalid or unreadable SHA256 file: ${sha_file}"
  printf '%s  %s\n' "${expected}" "${file}" | sha256sum --check --strict
}

is_flatcar() (
  local os_release_file="${NODE_CONFORMANCE_OS_RELEASE_FILE:-/etc/os-release}"
  local id=""
  local id_like=""

  set +u
  if [[ -r "${os_release_file}" ]]; then
    # shellcheck disable=SC1090
    . "${os_release_file}"
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  id="$(printf '%s' "${id}" | tr '[:upper:]' '[:lower:]')"
  id_like="$(printf '%s' "${id_like}" | tr '[:upper:]' '[:lower:]')"
  [[ "${id}" == "flatcar" || " ${id_like} " == *" flatcar "* ]]
)

# node_conformance_download fetches a URL to a file. dl.k8s.io and the GitHub
# release CDN both fail intermittently, so retry, and cap each transfer so that
# a stalled download fails the run instead of hanging it until the Ginkgo
# timeout. Arguments: max seconds, output path, url.
node_conformance_download() {
  local max_time="$1"
  local output="$2"
  local url="$3"

  curl --fail --silent --show-error --location \
    --retry 3 --retry-delay 5 --retry-connrefused \
    --connect-timeout 30 --max-time "${max_time}" \
    --output "${output}" "${url}"
}

download_kubernetes_tests() {
  local kubernetes_version="$1"
  local go_arch="$2"
  local tarball_url="${NODE_CONFORMANCE_TARBALL_URL:-https://dl.k8s.io/v${kubernetes_version}/kubernetes-test-linux-${go_arch}.tar.gz}"
  local download_timeout="${NODE_CONFORMANCE_DOWNLOAD_TIMEOUT:-1800}"

  log "downloading Kubernetes test tarball: ${tarball_url}"
  node_conformance_download "${download_timeout}" \
    "${work_dir}/kubernetes-test.tar.gz" "${tarball_url}"
  node_conformance_download 120 \
    "${work_dir}/kubernetes-test.tar.gz.sha256" "${tarball_url}.sha256"
  verify_sha256_file \
    "${work_dir}/kubernetes-test.tar.gz" \
    "${work_dir}/kubernetes-test.tar.gz.sha256"

  tar -xzf "${work_dir}/kubernetes-test.tar.gz" -C "${work_dir}" \
    kubernetes/test/bin/e2e_node.test \
    kubernetes/test/bin/ginkgo

  e2e_node_test="${work_dir}/kubernetes/test/bin/e2e_node.test"
  ginkgo_bin="${work_dir}/kubernetes/test/bin/ginkgo"
  chmod +x "${e2e_node_test}" "${ginkgo_bin}"
}

ensure_etcd() {
  local go_arch="$1"
  local etcd_version="${NODE_CONFORMANCE_ETCD_VERSION:-v3.5.32}"
  local download_timeout="${NODE_CONFORMANCE_DOWNLOAD_TIMEOUT:-1800}"
  local etcd_url

  if command -v etcd >/dev/null 2>&1; then
    log "using etcd from PATH: $(command -v etcd)"
    return
  fi

  mkdir -p "${work_dir}/bin"
  etcd_url="https://github.com/etcd-io/etcd/releases/download/${etcd_version}/etcd-${etcd_version}-linux-${go_arch}.tar.gz"
  log "downloading etcd ${etcd_version}: ${etcd_url}"
  node_conformance_download "${download_timeout}" "${work_dir}/etcd.tar.gz" "${etcd_url}"
  tar -xzf "${work_dir}/etcd.tar.gz" -C "${work_dir}"
  install -m 0755 \
    "${work_dir}/etcd-${etcd_version}-linux-${go_arch}/etcd" \
    "${work_dir}/bin/etcd"
  export PATH="${work_dir}/bin:${PATH}"
}

runtime_endpoint() {
  local sock

  for sock in \
    /run/containerd/containerd.sock \
    /var/run/containerd/containerd.sock \
    /var/run/crio/crio.sock; do
    if [[ -S "${sock}" ]]; then
      printf 'unix://%s\n' "${sock}"
      return
    fi
  done

  die "no CRI runtime socket found"
}

runtime_process_name() {
  local runtime_binary

  case "$1" in
    unix:///run/containerd/containerd.sock | unix:///var/run/containerd/containerd.sock)
      runtime_binary="$(command -v containerd || true)"
      printf '%s\n' "${runtime_binary:-/usr/local/bin/containerd}"
      ;;
    unix:///var/run/crio/crio.sock)
      runtime_binary="$(command -v crio || true)"
      printf '%s\n' "${runtime_binary:-/usr/bin/crio}"
      ;;
    *)
      printf 'containerd\n'
      ;;
  esac
}

ensure_container_runtime() {
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl start containerd >/dev/null 2>&1 || true
    sudo systemctl start crio >/dev/null 2>&1 || true
  fi
}

ensure_cni_config() {
  local plugin

  for plugin in bridge host-local loopback portmap; do
    [[ -x "${cni_bin_dir}/${plugin}" ]] ||
      die "required CNI plugin is missing or not executable: ${cni_bin_dir}/${plugin}"
  done

  sudo mkdir -p "${cni_conf_dir}"
  if sudo find "${cni_conf_dir}" -mindepth 1 -maxdepth 1 -type f -print -quit |
    grep -q .; then
    log "using existing CNI config in ${cni_conf_dir}"
    return
  fi

  sudo mkdir -p "${cni_data_dir}"
  log "creating CNI config: ${cni_conf_dir}/10-node-conformance.conflist"
  cat <<JSON | sudo tee "${cni_conf_dir}/10-node-conformance.conflist" >/dev/null
{
  "cniVersion": "1.0.0",
  "name": "node-conformance",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "promiscMode": true,
      "ipam": {
        "type": "host-local",
        "dataDir": "${cni_data_dir}",
        "ranges": [
          [{ "subnet": "10.88.0.0/16" }]
        ],
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": { "portMappings": true }
    }
  ]
}
JSON
}

stop_system_kubelet() {
  if command -v systemctl >/dev/null 2>&1 &&
    systemctl list-unit-files kubelet.service >/dev/null 2>&1; then
    log "stopping system kubelet before e2e-node starts its own kubelet"
    sudo systemctl stop kubelet || true
  fi
}

# publish_results records the final exit code and hands the results directory to
# the invoking SSH user so hack/qemu-node-conformance.sh can copy it out.
publish_results() {
  local exit_code=$?

  set +e
  if [[ -n "${results_dir:-}" ]]; then
    sudo mkdir -p "${results_dir}"
    printf 'exit_code=%s\n' "${exit_code}" | sudo tee "${results_dir}/summary.env" >/dev/null
    sudo chown -R "$(id -u):$(id -g)" "${results_dir}"
  fi

  exit "${exit_code}"
}

run_e2e_node() {
  local endpoint="$1"
  local process_name="$2"
  local node_name="${NODE_CONFORMANCE_NODE_NAME:-$(hostname)}"
  local k8s_bin_dir="${NODE_CONFORMANCE_K8S_BIN_DIR:-/usr/bin}"
  local focus="${NODE_CONFORMANCE_FOCUS:-\\[Conformance\\]}"
  local skip="${NODE_CONFORMANCE_SKIP:-\\[Flaky\\]|\\[Slow\\]}"
  local timeout="${NODE_CONFORMANCE_TIMEOUT:-2h}"
  local parallelism="${NODE_CONFORMANCE_PARALLELISM:-1}"
  local flake_attempts="${NODE_CONFORMANCE_FLAKE_ATTEMPTS:-1}"
  local kubelet_flags="${NODE_CONFORMANCE_KUBELET_FLAGS:---fail-swap-on=false --runtime-cgroups=/system.slice/containerd.service}"
  local kubelet_root_dir="${NODE_CONFORMANCE_KUBELET_ROOT_DIR:-${work_dir}/kubelet}"
  local standalone_mode="${NODE_CONFORMANCE_STANDALONE_MODE:-false}"
  local -a ginkgo_args
  local -a test_args
  local exit_code=0

  if [[ " ${kubelet_flags} " != *" --root-dir="* ]]; then
    kubelet_flags+=" --root-dir=${kubelet_root_dir}"
  fi
  if [[ " ${kubelet_flags} " != *" --cert-dir="* ]]; then
    kubelet_flags+=" --cert-dir=${kubelet_root_dir}/pki"
  fi

  ginkgo_args=(
    "--nodes=${parallelism}"
    "--flake-attempts=${flake_attempts}"
    "--focus=${focus}"
    "--skip=${skip}"
    "--timeout=${timeout}"
    "--v"
  )

  test_args=(
    "--node-name=${node_name}"
    "--k8s-bin-dir=${k8s_bin_dir}"
    "--container-runtime-endpoint=${endpoint}"
    "--container-runtime-process-name=${process_name}"
    "--container-runtime-pid-file="
    "--kubelet-flags=${kubelet_flags}"
    "--report-dir=${results_dir}"
    "--report-prefix=node-conformance"
  )

  if is_true "${standalone_mode}"; then
    test_args+=("--standalone-mode=true")
  fi

  log "running e2e_node.test focus=${focus} skip=${skip} parallelism=${parallelism}"
  # The e2e framework writes kubeconfig, kubelet-config and static-pod manifests
  # into its working directory, so run it from the work dir instead of the SSH
  # user's home.
  (
    cd "${work_dir}"
    set +e
    sudo -E env "PATH=${PATH}" "${ginkgo_bin}" "${ginkgo_args[@]}" \
      "${e2e_node_test}" -- "${test_args[@]}" 2>&1 |
      tee "${results_dir}/e2e_node.log"
    exit "${PIPESTATUS[0]}"
  ) || exit_code=$?

  return "${exit_code}"
}

main() {
  local kubernetes_version
  local go_arch
  local endpoint
  local process_name

  results_dir="${NODE_CONFORMANCE_RESULTS_DIR:-/tmp/kubernetes-node-conformance-results}"
  mkdir -p "${results_dir}"
  trap publish_results EXIT

  if is_flatcar; then
    die "node conformance is not supported on Flatcar images"
  fi

  require_cmd curl
  require_cmd sha256sum
  require_cmd sudo
  require_cmd tar

  work_dir="${NODE_CONFORMANCE_WORK_DIR:-$(mktemp -d /tmp/node-conformance.XXXXXX)}"
  cni_conf_dir="${NODE_CONFORMANCE_CNI_CONF_DIR:-/etc/cni/net.d}"
  cni_bin_dir="${NODE_CONFORMANCE_CNI_BIN_DIR:-/opt/cni/bin}"
  cni_data_dir="${NODE_CONFORMANCE_CNI_DATA_DIR:-${work_dir}/cni/networks}"

  kubernetes_version="${KUBERNETES_VERSION:-}"
  if [[ -z "${kubernetes_version}" ]]; then
    kubernetes_version="$(detect_kubernetes_version)"
  fi
  kubernetes_version="$(normalize_kubernetes_version "${kubernetes_version}")"
  go_arch="$(detect_go_arch)"

  download_kubernetes_tests "${kubernetes_version}" "${go_arch}"
  ensure_etcd "${go_arch}"
  ensure_container_runtime
  endpoint="$(runtime_endpoint)"
  process_name="$(runtime_process_name "${endpoint}")"
  ensure_cni_config
  stop_system_kubelet

  log "Kubernetes v${kubernetes_version}; runtime endpoint ${endpoint}"
  run_e2e_node "${endpoint}" "${process_name}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
