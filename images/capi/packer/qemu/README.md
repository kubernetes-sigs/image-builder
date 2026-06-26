To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make build-kubevirt-qemu-ubuntu-2404

P.S: In order to change disk size(defaults to 20GB as of 31.10.22) you can update PACKER_FLAGS with:
--var 'disk_size=<disk size in mb>'

## Boot smoke test

After building a QEMU image, you can run an optional local boot smoke test
against the output image:

```bash
make test-qemu-boot-smoke QEMU_BOOT_SMOKE_IMAGE=output/ubuntu-2404-kube-v1.33.0
```

The target starts the image with QEMU, using a temporary copy-on-write overlay so
the built artifact is not modified. By default it also attaches a temporary
NoCloud seed ISO that creates an SSH user from `cloudinit/id_rsa.capi.pub`, then
waits for SSH on `127.0.0.1:2222`.

The smoke test is opt-in and is not wired into required CI. It is intended for
local validation of already-built QEMU images. Common overrides:

```bash
QEMU_SSH_PORT=2223 \
QEMU_SSH_TIMEOUT=900 \
QEMU_SMOKE_COMMAND='cloud-init status --wait' \
make test-qemu-boot-smoke QEMU_BOOT_SMOKE_IMAGE=output/ubuntu-2404-kube-v1.33.0
```

Use `QEMU_BOOT_SMOKE_ARGS='-- ...'` to pass additional QEMU arguments, such as
firmware options for an EFI image.

For images that already contain test SSH access, disable the generated cloud-init
seed and provide the matching credentials:

```bash
QEMU_SEED=none \
QEMU_SSH_USER=builder \
QEMU_SSH_PRIVATE_KEY=/path/to/key \
make test-qemu-boot-smoke QEMU_BOOT_SMOKE_IMAGE=/path/to/image.qcow2
```
