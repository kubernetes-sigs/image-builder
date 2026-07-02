To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make build-kubevirt-qemu-ubuntu-2404

P.S: In order to change disk size(defaults to 20GB as of 31.10.22) you can update PACKER_FLAGS with:
--var 'disk_size=<disk size in mb>'

## Ubuntu immutable target

The `qemu-ubuntu-2404-immutable` target builds an Ubuntu image with a separate
persistent data partition. The OS root partition remains writable while Packer
and Ansible provision the image; when `immutable_read_only_root=true`, the final
image is configured so `/` mounts read-only on the next boot.

The immutable target can be tuned with normal Packer variables:

```bash
PACKER_FLAGS="\
  --var 'immutable_data_partition_label=CAPI-DATA' \
  --var 'immutable_data_partition_mount=/var/lib/cluster-api-data' \
  --var 'immutable_data_partition_mount_options=defaults,nofail' \
  --var 'immutable_root_partition_size=12884901888' \
  --var 'immutable_read_only_root=true'" \
  make build-qemu-ubuntu-2404-immutable
```

Supported immutable variables:

- `immutable_data_partition`: create and mount the data partition when `true`.
- `immutable_data_partition_fstype`: filesystem type for the data partition; currently `ext4`.
- `immutable_data_partition_label`: filesystem label for the data partition.
- `immutable_data_partition_mount`: mount point for persistent runtime data.
- `immutable_data_partition_mount_options`: fstab options for the data partition.
- `immutable_root_partition_size`: root partition size in bytes; the data partition uses the remaining disk.
- `immutable_read_only_root`: write `/` as read-only in `/etc/fstab` for the final image.

The target validates the contract in three places:

- the Ubuntu autoinstall renderer unit tests verify root/data partition
  rendering and input validation;
- `packer validate` verifies the QEMU target, Packer variables, and Goss
  variable wiring;
- Goss verifies that the built image has the labeled data partition mounted,
  the data mount is writable, and `/etc/fstab` marks `/` read-only when
  `immutable_read_only_root=true`.

The image root remains writable during Packer provisioning. The read-only root
state is applied through `/etc/fstab` for the next boot so normal Ansible
provisioning and Goss checks can complete before the image is finalized.

Run the focused immutable validation with:

```bash
make test-qemu-immutable
make validate-qemu-ubuntu-2404-immutable
```
