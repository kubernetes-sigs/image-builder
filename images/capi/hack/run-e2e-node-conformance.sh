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

set -euo pipefail

log() {
  printf '[node-conformance] %s\n' "$*" >&2
}

die() {
  printf '[node-conformance] ERROR: %s\n' "$*" >&2
  exit 1
}

is_true() {
  case "${1:-false}" in
    true | TRUE | True | 1 | yes | YES | Yes) return 0 ;;
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

verify_sha256_file() {
  local file="$1"
  local sha_file="$2"
  local expected

  read -r expected _ <"${sha_file}" || die "cannot read SHA256 file: ${sha_file}"
  [[ "${expected}" =~ ^[A-Fa-f0-9]{64}$ ]] || die "invalid SHA256 file: ${sha_file}"
  printf '%s  %s\n' "${expected}" "${file}" | sha256sum --check --strict
}

download_kubernetes_tests() {
  local kubernetes_version="$1"
  local go_arch="$2"
  local tarball_url="${NODE_CONFORMANCE_TARBALL_URL:-https://dl.k8s.io/v${kubernetes_version}/kubernetes-test-linux-${go_arch}.tar.gz}"

  log "downloading Kubernetes test tarball: ${tarball_url}"
  curl --fail --silent --show-error --location \
    --output "${work_dir}/kubernetes-test.tar.gz" \
    "${tarball_url}"
  curl --fail --silent --show-error --location \
    --output "${work_dir}/kubernetes-test.tar.gz.sha256" \
    "${tarball_url}.sha256"
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
  local etcd_url

  if command -v etcd >/dev/null 2>&1; then
    log "using etcd from PATH: $(command -v etcd)"
    return
  fi

  mkdir -p "${work_dir}/bin"
  etcd_url="https://github.com/etcd-io/etcd/releases/download/${etcd_version}/etcd-${etcd_version}-linux-${go_arch}.tar.gz"
  log "downloading etcd ${etcd_version}: ${etcd_url}"
  curl --fail --silent --show-error --location \
    --output "${work_dir}/etcd.tar.gz" \
    "${etcd_url}"
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
  local cni_conf_dir="${NODE_CONFORMANCE_CNI_CONF_DIR:-/etc/cni/net.d}"
  local cni_bin_dir="${NODE_CONFORMANCE_CNI_BIN_DIR:-/opt/cni/bin}"
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

  created_cni_config="${cni_conf_dir}/10-node-conformance.conflist"
  log "creating temporary CNI config: ${created_cni_config}"
  cat <<'EOF' | sudo tee "${created_cni_config}" >/dev/null
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
EOF
}

stop_system_kubelet() {
  if command -v systemctl >/dev/null 2>&1 &&
    systemctl list-unit-files kubelet.service >/dev/null 2>&1; then
    log "stopping system kubelet before e2e-node starts its own kubelet"
    sudo systemctl stop kubelet || true
  fi
}

cleanup_runtime_state() {
  local current_cri_images_file

  set +e

  if [[ -n "${created_cni_config:-}" ]]; then
    sudo rm -f "${created_cni_config}"
  fi

  if command -v crictl >/dev/null 2>&1; then
    sudo crictl rm --all >/dev/null 2>&1
    if [[ -n "${preexisting_cri_images_file:-}" && -f "${preexisting_cri_images_file}" ]]; then
      current_cri_images_file="${work_dir}/current-cri-images.txt"
      if sudo crictl images -q 2>/dev/null | sort -u >"${current_cri_images_file}"; then
        comm -13 "${preexisting_cri_images_file}" "${current_cri_images_file}" |
          xargs -r sudo crictl rmi >/dev/null 2>&1
      fi
    fi
  fi

  if command -v ctr >/dev/null 2>&1; then
    sudo ctr -n k8s.io containers ls -q |
      xargs -r sudo ctr -n k8s.io containers rm >/dev/null 2>&1
  fi

  if [[ "${NODE_CONFORMANCE_KEEP_WORK_DIR:-false}" != "true" ]]; then
    rm -rf "${work_dir}"
  else
    log "kept work dir: ${work_dir}"
  fi
}

snapshot_runtime_images() {
  preexisting_cri_images_file=""
  if command -v crictl >/dev/null 2>&1; then
    preexisting_cri_images_file="${work_dir}/preexisting-cri-images.txt"
    if ! sudo crictl images -q 2>/dev/null | sort -u >"${preexisting_cri_images_file}"; then
      rm -f "${preexisting_cri_images_file}"
      preexisting_cri_images_file=""
    fi
  fi
}

run_e2e_node() {
  local endpoint="$1"
  local process_name="$2"
  local node_name="${NODE_CONFORMANCE_NODE_NAME:-$(hostname)}"
  local k8s_bin_dir="${NODE_CONFORMANCE_K8S_BIN_DIR:-/usr/bin}"
  local focus="${NODE_CONFORMANCE_FOCUS:-\\[Conformance\\]}"
  local skip="${NODE_CONFORMANCE_SKIP:-\\[Flaky\\]|\\[Serial\\]|\\[Slow\\]}"
  local timeout="${NODE_CONFORMANCE_TIMEOUT:-2h}"
  local parallelism="${NODE_CONFORMANCE_PARALLELISM:-4}"
  local flake_attempts="${NODE_CONFORMANCE_FLAKE_ATTEMPTS:-1}"
  local kubelet_flags="${NODE_CONFORMANCE_KUBELET_FLAGS:---fail-swap-on=false --runtime-cgroups=/system.slice/containerd.service}"
  local standalone_mode="${NODE_CONFORMANCE_STANDALONE_MODE:-true}"
  local -a ginkgo_args
  local -a test_args
  local exit_code

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
    "--container-runtime=remote"
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
  set +e
  sudo -E "${ginkgo_bin}" "${ginkgo_args[@]}" "${e2e_node_test}" -- "${test_args[@]}" \
    2>&1 | tee "${results_dir}/e2e_node.log"
  exit_code="${PIPESTATUS[0]}"
  set -e

  printf 'exit_code=%s\n' "${exit_code}" >"${results_dir}/summary.env"
  return "${exit_code}"
}

results_dir="${NODE_CONFORMANCE_RESULTS_DIR:-/tmp/kubernetes-node-conformance-results}"
mkdir -p "${results_dir}"

if ! is_true "${KUBERNETES_NODE_CONFORMANCE:-false}"; then
  log "disabled; set KUBERNETES_NODE_CONFORMANCE=true to run"
  printf 'disabled=true\n' >"${results_dir}/summary.env"
  exit 0
fi

: "${KUBERNETES_VERSION:?KUBERNETES_VERSION is required}"
require_cmd curl
require_cmd sha256sum
require_cmd sudo
require_cmd tar

created_cni_config=""
work_dir="${NODE_CONFORMANCE_WORK_DIR:-$(mktemp -d /tmp/node-conformance.XXXXXX)}"
trap cleanup_runtime_state EXIT

kubernetes_version="$(normalize_kubernetes_version "${KUBERNETES_VERSION}")"
go_arch="$(detect_go_arch)"

download_kubernetes_tests "${kubernetes_version}" "${go_arch}"
ensure_etcd "${go_arch}"
ensure_container_runtime
endpoint="$(runtime_endpoint)"
process_name="$(runtime_process_name "${endpoint}")"
snapshot_runtime_images
ensure_cni_config
stop_system_kubelet

log "Kubernetes v${kubernetes_version}; runtime endpoint ${endpoint}"
run_e2e_node "${endpoint}" "${process_name}"
