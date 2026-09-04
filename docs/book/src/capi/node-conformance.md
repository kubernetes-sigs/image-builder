# Kubernetes Node Conformance

Image Builder can run the Kubernetes `e2e_node.test` conformance subset against
an already built QEMU image. It is a post-build validation step, not part of the
image build.

`hack/qemu-node-conformance.sh` boots the built image from a throwaway qcow2
copy-on-write overlay with a temporary NoCloud seed ISO, copies the conformance
hook into the guest over SSH, runs it, copies the results back out, and then
discards the overlay. The built image is only ever read from, so a conformance
run cannot leave kubelet, CNI, runtime, or test state in the shipped artifact.

Conformance is not run by default. It downloads the version-matched Kubernetes
test tarball and adds significant runtime, so it is meant for release or
periodic image validation jobs rather than every local or presubmit build.

## Usage

Build an image, then validate it:

```bash
cd images/capi
make build-qemu-ubuntu-2404
make test-qemu-node-conformance QEMU_NODE_CONFORMANCE_IMAGE=output/ubuntu-2404-kube-v1.33.0
```

`QEMU_NODE_CONFORMANCE_IMAGE` accepts either a Packer output directory holding
exactly one disk image or a path to the image itself. Use
`QEMU_NODE_CONFORMANCE_ARGS='-- ...'` to pass additional QEMU arguments.

The helper script can also be called directly:

```bash
cd images/capi
hack/qemu-node-conformance.sh output/ubuntu-2404-kube-v1.33.0
```

From the repository root, the CI entry point builds and validates in one step
with defaults suitable for a nested-virtualization runner:

```bash
images/capi/scripts/ci-qemu-node-conformance.sh
```

It builds `build-qemu-ubuntu-2404-cloudimg` by default, then runs conformance
against the produced artifact with KVM acceleration, 4 CPUs, and 8 GiB of
memory. Override `NODE_CONFORMANCE_TARGET`, `NODE_CONFORMANCE_CPUS`,
`NODE_CONFORMANCE_MEMORY`, or `NODE_CONFORMANCE_ACCELERATOR` to tune a run. It
requires `/dev/kvm` unless `NODE_CONFORMANCE_ACCELERATOR=tcg` is set explicitly
for slower local debugging.

Inside the guest, the hook downloads `kubernetes-test-linux-${ARCH}.tar.gz` for
the Kubernetes version reported by the image's own kubelet, starts the local CRI
runtime, stops the system kubelet, and runs `e2e_node.test` with a default focus
of `[Conformance]`.

Each run writes its results into a fresh timestamped subdirectory of
`node-conformance-results/`, before the exit status is evaluated, so logs and
JUnit reports are preserved even when the run fails. Nothing under
`NODE_CONFORMANCE_OUTPUT_DIR` is ever deleted, so repeated runs accumulate side
by side and pointing the variable at an existing directory is safe. A missing or
unparsable `summary.env` is treated as a failure.

Flatcar targets are excluded. Flatcar uses Ignition rather than cloud-init and
the build removes the SSH user before shutdown, so the guest cannot be reached
over SSH. Set `QEMU_IMAGE_OS=flatcar` to fail fast.

## Configuration

Both scripts are configured with environment variables.

`hack/qemu-node-conformance.sh` shares the QEMU and SSH variables documented by
`hack/qemu-boot-smoke.sh` (`QEMU_BINARY`, `QEMU_IMG`, `QEMU_ACCELERATOR`,
`QEMU_MACHINE`, `QEMU_SSH_PORT`, `QEMU_SSH_USER`, ...), with these defaults
raised for a conformance workload:

| Variable | Default | Description |
| --- | --- | --- |
| `QEMU_CPUS` | `4` | vCPUs given to the guest. |
| `QEMU_MEMORY` | `4096` | Guest memory in MiB. |
| `QEMU_SSH_TIMEOUT` | `900` | Seconds to wait for SSH after boot. |
| `NODE_CONFORMANCE_OUTPUT_DIR` | `node-conformance-results` | Host directory that per-run result subdirectories are created in. |

The conformance run itself is tuned with the following variables, which are
forwarded into the guest:

| Variable | Default | Description |
| --- | --- | --- |
| `KUBERNETES_VERSION` | detected from the guest kubelet | Version of the test tarball to download. |
| `NODE_CONFORMANCE_FOCUS` | `\[Conformance\]` | Ginkgo focus expression. |
| `NODE_CONFORMANCE_SKIP` | `\[Flaky\]\|\[Slow\]` | Ginkgo skip expression. |
| `NODE_CONFORMANCE_PARALLELISM` | `1` | Ginkgo parallel node count. |
| `NODE_CONFORMANCE_FLAKE_ATTEMPTS` | `1` | Ginkgo flake attempts. |
| `NODE_CONFORMANCE_TIMEOUT` | `2h` | Ginkgo timeout for the e2e-node run. |
| `NODE_CONFORMANCE_STANDALONE_MODE` | `false` | Passes `--standalone-mode=true` to `e2e_node.test`. |
| `NODE_CONFORMANCE_KUBELET_FLAGS` | `--fail-swap-on=false --runtime-cgroups=/system.slice/containerd.service` | Extra kubelet flags passed to `e2e_node.test`. |
| `NODE_CONFORMANCE_ETCD_VERSION` | `v3.5.32` | etcd version downloaded when `etcd` is not already installed. |
| `NODE_CONFORMANCE_DOWNLOAD_TIMEOUT` | `1800` | Seconds any single large download may take before it fails. |
| `NODE_CONFORMANCE_RESULTS_DIR` | `/tmp/kubernetes-node-conformance-results` | Guest result directory that is downloaded. |

`NODE_CONFORMANCE_STANDALONE_MODE` defaults to `false` because standalone mode
starts the kubelet without a `--kubeconfig`, so it never joins the test
apiserver and conformance pods cannot be scheduled.

Example with a custom focus and two parallel nodes:

```bash
cd images/capi
NODE_CONFORMANCE_PARALLELISM=2 \
  NODE_CONFORMANCE_FOCUS='\[Conformance\]' \
  hack/qemu-node-conformance.sh output/ubuntu-2404-kube-v1.33.0
```

## Scope

Node conformance validates a node image in isolation. It complements Goss image
checks, but it does not replace Cluster API provider e2e tests or Kubernetes
cluster conformance suites that need a bootstrapped cluster.

References:

- Kubernetes node conformance: <https://kubernetes.io/docs/setup/best-practices/node-conformance/>
- SIG Node e2e-node tests: <https://github.com/kubernetes/community/blob/main/contributors/devel/sig-node/e2e-node-tests.md>
