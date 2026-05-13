#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# Run the Kubernetes node-conformance subset of the e2e_node test suite on the
# local machine.  Intended to be executed on a freshly-booted VM created from a
# CAPI image-builder image, _not_ on a node that is already part of a cluster.
#
# This is a best-effort runner that pulls the official versioned kubernetes-test
# tarball from dl.k8s.io (matched to the Kubernetes version baked into the
# image) and invokes ./e2e_node.test in standalone mode so the framework can
# start its own kubelet against the system's container runtime.
#
# Results (JUnit XML + ginkgo logs) are written to /tmp/node-conformance-results.
#
# Environment variables:
#   KUBERNETES_VERSION   Required. e.g. "1.31.1" (no leading "v")
#   GINKGO_FOCUS         Optional. Default '\[NodeConformance\]'
#   GINKGO_SKIP          Optional. Default '\[Flaky\]|\[Serial\]|\[Slow\]|\[Alpha\]'
#   RESULTS_DIR          Optional. Default /tmp/node-conformance-results
#   TARBALL_URL          Optional. Override the test tarball URL.
#   TARBALL_SHA256_URL   Optional. Override the checksum URL. Defaults to
#                        "${TARBALL_URL}.sha256". The remote file is expected
#                        to contain just the hex digest (as dl.k8s.io serves).
#
# Exit code is the exit code of e2e_node.test (non-zero on any failed spec).

set -o errexit
set -o nounset
set -o pipefail

KUBERNETES_VERSION="${KUBERNETES_VERSION:?KUBERNETES_VERSION is required, e.g. 1.31.1}"
GINKGO_FOCUS="${GINKGO_FOCUS:-\[NodeConformance\]}"
GINKGO_SKIP="${GINKGO_SKIP:-\[Flaky\]|\[Serial\]|\[Slow\]|\[Alpha\]}"
RESULTS_DIR="${RESULTS_DIR:-/tmp/node-conformance-results}"

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)  GO_ARCH="amd64" ;;
  aarch64) GO_ARCH="arm64" ;;
  *)       echo "unsupported arch: ${ARCH}" >&2; exit 1 ;;
esac

TARBALL_URL="${TARBALL_URL:-https://dl.k8s.io/v${KUBERNETES_VERSION}/kubernetes-test-linux-${GO_ARCH}.tar.gz}"
TARBALL_SHA256_URL="${TARBALL_SHA256_URL:-${TARBALL_URL}.sha256}"

WORKDIR="$(mktemp -d)"

# klog.Fatalf inside e2e_node.test exits with 255 — the same code ssh uses
# for its own transport/auth errors. Translate 255 -> 254 on the way out so
# the calling workflow can tell the two apart.
# shellcheck disable=SC2329  # invoked via trap
cleanup() {
  local rc=$?
  rm -rf "${WORKDIR}"
  if [[ "${rc}" -eq 255 ]]; then
    echo "==> Translating exit 255 -> 254 to disambiguate from SSH transport failure" >&2
    exit 254
  fi
  exit "${rc}"
}
trap cleanup EXIT

echo "==> Node conformance: kubernetes v${KUBERNETES_VERSION} (${GO_ARCH})"
echo "    focus:   ${GINKGO_FOCUS}"
echo "    skip:    ${GINKGO_SKIP}"
echo "    results: ${RESULTS_DIR}"
echo "    tarball: ${TARBALL_URL}"

mkdir -p "${RESULTS_DIR}"
sudo chown "$(id -u):$(id -g)" "${RESULTS_DIR}"

echo "==> Downloading test tarball"
curl --fail --silent --show-error --location \
  --output "${WORKDIR}/test.tar.gz" "${TARBALL_URL}"

echo "==> Downloading tarball SHA-256 checksum"
curl --fail --silent --show-error --location \
  --output "${WORKDIR}/test.tar.gz.sha256" "${TARBALL_SHA256_URL}"

echo "==> Verifying tarball checksum"
# dl.k8s.io publishes the bare hex digest (no filename); build a sha256sum
# compatible line so we can use the standard verifier.
EXPECTED_SHA256="$(tr -d '[:space:]' < "${WORKDIR}/test.tar.gz.sha256")"
if [[ -z "${EXPECTED_SHA256}" ]]; then
  echo "ERROR: empty checksum retrieved from ${TARBALL_SHA256_URL}" >&2
  exit 1
fi
echo "${EXPECTED_SHA256}  test.tar.gz" > "${WORKDIR}/test.tar.gz.sha256sum"
( cd "${WORKDIR}" && sha256sum --check --strict --status test.tar.gz.sha256sum ) || {
  ACTUAL_SHA256="$(sha256sum "${WORKDIR}/test.tar.gz" | awk '{print $1}')"
  echo "ERROR: SHA-256 mismatch for ${TARBALL_URL}" >&2
  echo "  expected: ${EXPECTED_SHA256}" >&2
  echo "  actual:   ${ACTUAL_SHA256}" >&2
  exit 1
}
echo "    OK (${EXPECTED_SHA256})"

echo "==> Extracting e2e_node.test and ginkgo"
tar -xzf "${WORKDIR}/test.tar.gz" -C "${WORKDIR}" \
  kubernetes/test/bin/e2e_node.test \
  kubernetes/test/bin/ginkgo
E2E_NODE_TEST="${WORKDIR}/kubernetes/test/bin/e2e_node.test"
GINKGO_BIN="${WORKDIR}/kubernetes/test/bin/ginkgo"
chmod +x "${E2E_NODE_TEST}" "${GINKGO_BIN}"

# The framework starts its own kubelet under test, so stop the system unit (if
# any) to free /var/lib/kubelet and the kubelet socket.  Don't fail if absent.
if systemctl list-unit-files kubelet.service >/dev/null 2>&1; then
  echo "==> Stopping system kubelet"
  sudo systemctl stop kubelet || true
fi

# Detect the system container runtime endpoint and its systemd cgroup path.
RUNTIME_ENDPOINT=""
RUNTIME_CGROUP=""
for sock in /run/containerd/containerd.sock /var/run/containerd/containerd.sock /var/run/crio/crio.sock; do
  if [[ -S "${sock}" ]]; then
    RUNTIME_ENDPOINT="unix://${sock}"
    case "${sock}" in
      */crio.sock)       RUNTIME_CGROUP="/system.slice/crio.service" ;;
      */containerd.sock) RUNTIME_CGROUP="/system.slice/containerd.service" ;;
    esac
    break
  fi
done
if [[ -z "${RUNTIME_ENDPOINT}" ]]; then
  echo "ERROR: no container runtime socket found" >&2
  exit 1
fi
echo "==> Using container runtime endpoint: ${RUNTIME_ENDPOINT}"
echo "==> Using runtime cgroup: ${RUNTIME_CGROUP}"

# Locate the kubelet binary that was baked into the image; the test framework
# will exec it.
KUBELET_BIN="$(command -v kubelet || true)"
if [[ -z "${KUBELET_BIN}" ]]; then
  for candidate in /usr/local/bin/kubelet /usr/bin/kubelet /opt/bin/kubelet; do
    if [[ -x "${candidate}" ]]; then KUBELET_BIN="${candidate}"; break; fi
  done
fi
if [[ -z "${KUBELET_BIN}" ]]; then
  echo "ERROR: kubelet binary not found on PATH" >&2
  exit 1
fi
echo "==> Using kubelet binary: ${KUBELET_BIN}"

NODE_NAME="$(hostname)"

echo "==> Running e2e_node.test"
# --k8s-bin-dir tells the test framework where to find the kubelet binary
# it will exec under test (the version-matched binary already baked into
# the image).  Without it the framework falls back to looking for a
# kubernetes source checkout at _output/local/go/bin/kubelet.
KUBELET_BIN_DIR="$(dirname "${KUBELET_BIN}")"
set +e
sudo -E "${E2E_NODE_TEST}" \
  --node-name="${NODE_NAME}" \
  --standalone-mode=true \
  --k8s-bin-dir="${KUBELET_BIN_DIR}" \
  --kubelet-flags="--cgroup-driver=systemd --container-runtime-endpoint=${RUNTIME_ENDPOINT} --runtime-cgroups=${RUNTIME_CGROUP}" \
  --container-runtime-endpoint="${RUNTIME_ENDPOINT}" \
  --ginkgo.focus="${GINKGO_FOCUS}" \
  --ginkgo.skip="${GINKGO_SKIP}" \
  --ginkgo.timeout=2h \
  --ginkgo.v \
  --report-dir="${RESULTS_DIR}" \
  --report-prefix="node-conformance" \
  2>&1 | tee "${RESULTS_DIR}/e2e_node.log"
EXIT_CODE=${PIPESTATUS[0]}
set -e

# Make results readable for the calling user (scp back).
sudo chown -R "$(id -u):$(id -g)" "${RESULTS_DIR}" || true

echo "==> e2e_node.test exited with ${EXIT_CODE}"
exit "${EXIT_CODE}"
