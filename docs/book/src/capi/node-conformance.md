# Kubernetes Node Conformance

Image Builder can run the Kubernetes `e2e_node.test` conformance subset as an
optional QEMU image validation step after the normal Goss checks.

The hook is disabled by default because it downloads the version-matched
Kubernetes test tarball and adds significant runtime. Enable it for manual
validation when you need stronger signal that a newly built node image can run a
conformant kubelet and container runtime.

## QEMU Usage

Run a QEMU build with node conformance enabled:

```bash
cd images/capi
PACKER_FLAGS="--var 'node_conformance=true'" make build-qemu-ubuntu-2404
```

The runner downloads `kubernetes-test-linux-${ARCH}.tar.gz` for the same
Kubernetes version configured by `kubernetes_semver`, starts the local CRI
runtime, stops the system kubelet, and runs `e2e_node.test` with a default focus
of `[Conformance]`.

Results are downloaded to `node-conformance-results/` before Packer evaluates
the test result. This preserves logs and JUnit/report files even when the
conformance run fails.

## Configuration

The defaults live in `packer/config/node-conformance.json` and can be overridden
with `PACKER_FLAGS` or an additional Packer var file.

| Variable | Default | Description |
| --- | --- | --- |
| `node_conformance` | `false` | Enables the QEMU node conformance hook. |
| `node_conformance_focus` | `\[Conformance\]` | Ginkgo focus expression. |
| `node_conformance_skip` | `\[Flaky\]\|\[Serial\]\|\[Slow\]` | Ginkgo skip expression. |
| `node_conformance_parallelism` | `4` | Ginkgo parallel node count. |
| `node_conformance_timeout` | `2h` | Ginkgo timeout for the e2e-node run. |
| `node_conformance_flake_attempts` | `1` | Ginkgo flake attempts. |
| `node_conformance_standalone_mode` | `true` | Passes `--standalone-mode=true` to `e2e_node.test`. |
| `node_conformance_kubelet_flags` | `--fail-swap-on=false --runtime-cgroups=/system.slice/containerd.service` | Extra kubelet flags passed to `e2e_node.test`. |
| `node_conformance_etcd_version` | `v3.5.32` | etcd version downloaded when `etcd` is not already installed. |
| `node_conformance_results_dir` | `/tmp/kubernetes-node-conformance-results` | Guest result directory downloaded by Packer. |

Example with custom focus and fewer parallel nodes:

```bash
cd images/capi
PACKER_FLAGS="--var 'node_conformance=true' \
  --var 'node_conformance_parallelism=2' \
  --var 'node_conformance_focus=\\[Conformance\\]'" \
  make build-qemu-ubuntu-2404
```

## Scope

Node conformance validates a node image in isolation. It complements Goss image
checks, but it does not replace Cluster API provider e2e tests or Kubernetes
cluster conformance suites that need a bootstrapped cluster.

References:

- Kubernetes node conformance: <https://kubernetes.io/docs/setup/best-practices/node-conformance/>
- SIG Node e2e-node tests: <https://github.com/kubernetes/community/blob/main/contributors/devel/sig-node/e2e-node-tests.md>
