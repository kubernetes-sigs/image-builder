To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make build-kubevirt-qemu-ubuntu-2404

P.S: In order to change disk size(defaults to 20GB as of 31.10.22) you can update PACKER_FLAGS with:
--var 'disk_size=<disk size in mb>'

To run the optional Kubernetes node conformance hook after the normal Goss
checks, enable `node_conformance`:

PACKER_FLAGS="--var 'node_conformance=true'" make build-qemu-ubuntu-2404

The hook downloads the version-matched Kubernetes `e2e_node.test` binary and
writes results to `node-conformance-results/`.

Node conformance is intentionally disabled by default. It is intended for
release or periodic image validation jobs where the added runtime is acceptable,
not for every local or presubmit image build.
