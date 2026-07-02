To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make build-kubevirt-qemu-ubuntu-2404

P.S: In order to change disk size(defaults to 20GB as of 31.10.22) you can update PACKER_FLAGS with:
--var 'disk_size=<disk size in mb>'

## Ubuntu immutable target

The `qemu-ubuntu-2404-immutable` target builds an Ubuntu image for Cluster API
with a read-only root filesystem and a separate persistent data partition. The
image root stays writable while Packer and Ansible provision the guest. The
immutable runtime script then adds the data partition, persistent bind mounts,
tmpfs mounts, and the read-only root fstab entry before Goss validates the final
guest contract.

Build a CAPI-ready Ubuntu 24.04 immutable image from `images/capi` with the
normal Kubernetes/containerd/CNI config files:

```bash
PACKER_VAR_FILES="packer/config/kubernetes.json packer/config/cni.json packer/config/containerd.json" \
PACKER_FLAGS="\
  --var 'format=qcow2' \
  --var 'kubernetes_semver=v1.36.1' \
  --var 'kubernetes_series=v1.36' \
  --var 'kubernetes_deb_version=1.36.1-1.1' \
  --var 'immutable_read_only_root=true'" \
  make build-qemu-ubuntu-2404-immutable
```

Use `--var 'format=raw'` instead when the target infrastructure consumes raw
disk images. The default output directory follows the normal QEMU naming
pattern, for example `output/ubuntu-2404-immutable-kube-v1.36.1`.

The target enables these immutable defaults:

- `immutable_data_partition=true`: create and mount the data partition.
- `immutable_data_partition_fstype=ext4`: filesystem type for the data partition.
- `immutable_data_partition_label=CAPI-DATA`: filesystem label for the data partition.
- `immutable_data_partition_mount=/var/lib/cluster-api-data`: mount point for persistent runtime data.
- `immutable_data_partition_mount_options=defaults,nofail`: fstab options for the data partition.
- `immutable_root_partition_size=12884901888`: root partition size in bytes; the data partition uses the remaining disk.
- `immutable_read_only_root=true`: write `/` as read-only in `/etc/fstab` for the final image.
- `immutable_persistent_paths=/etc/cloud,/etc/cni,/etc/containerd,/etc/kubernetes,/etc/modprobe.d,/etc/modules-load.d,/etc/netplan,/etc/ssh,/etc/sysctl.d,/etc/systemd,/var/lib/cloud,/var/lib/containerd,/var/lib/etcd,/var/lib/kubelet,/var/log`: copy existing contents into the data partition and bind mount them back for CAPI bootstrap and node runtime writes.
- `immutable_tmpfs_paths=/tmp,/var/tmp`: mount volatile scratch paths as tmpfs.

The persistent path list is intentionally explicit. It covers cloud-init state,
SSH host keys, systemd units and drop-ins, netplan and common kernel/network
drop-in directories, CNI/containerd/Kubernetes configuration, kubelet and
containerd state, optional etcd state for control-plane images, and logs.
Providers that write additional bootstrap files should extend
`immutable_persistent_paths` rather than making the whole root writable again.

The target validates the contract in four places:

- the Ubuntu autoinstall renderer unit tests verify root/data partition
  rendering and input validation;
- the immutable runtime unit tests verify fstab replacement, persistent bind
  mount generation, content copy, tmpfs generation, and the data-partition
  requirement for persistent paths;
- `packer validate` verifies the QEMU target, Packer variables, and Goss
  variable wiring;
- Goss runs after immutable runtime configuration and verifies the labeled data
  partition, writable data mount, writable persistent bind mounts, writable
  tmpfs paths, and read-only root fstab entry.

Run the focused immutable validation with:

```bash
make test-qemu-immutable
make validate-qemu-ubuntu-2404-immutable
```

These checks prove the image build contract. The provider or infrastructure
project should still boot the produced artifact through Cluster API and verify
that the Machine becomes Ready with the selected network and image delivery
path.
