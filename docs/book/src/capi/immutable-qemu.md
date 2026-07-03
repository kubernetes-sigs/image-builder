# Ubuntu immutable QEMU images

The `qemu-ubuntu-2404-immutable` target builds an Ubuntu 24.04 Cluster API
image with a read-only root filesystem and a separate persistent data
partition. Packer and Ansible provision the image while the root filesystem is
still writable. The final immutable runtime step creates the persistent data
partition, bind mounts the writable runtime paths, configures tmpfs scratch
paths, and writes `/` as read-only in `/etc/fstab` before Goss runs.

Build the target from `images/capi`:

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

Use `--var 'format=raw'` when the consuming provider expects a raw disk image.

## Immutable configuration

The target enables the data partition and read-only root by default. These
variables can be overridden through Packer variables when a provider needs a
different contract:

| Variable | Default |
| --- | --- |
| `immutable_data_partition` | `true` |
| `immutable_data_partition_fstype` | `ext4` |
| `immutable_data_partition_label` | `CAPI-DATA` |
| `immutable_data_partition_mount` | `/var/lib/cluster-api-data` |
| `immutable_data_partition_mount_options` | `defaults,nofail` |
| `immutable_root_partition_size` | `12884901888` |
| `immutable_read_only_root` | `true` |
| `immutable_persistent_paths` | `/etc,/home,/root,/opt/cni/bin,/var/cache,/var/lib/NetworkManager,/var/lib/calico,/var/lib/chrony,/var/lib/cilium,/var/lib/cloud,/var/lib/cni,/var/lib/containerd,/var/lib/dbus,/var/lib/etcd,/var/lib/kubelet,/var/lib/private,/var/lib/systemd,/var/log,/var/spool` |
| `immutable_tmpfs_paths` | `/tmp,/var/tmp` |

The persistent path list covers first-boot configuration under `/etc`,
cloud-init state, user home directories, SSH host keys, CNI binaries and
runtime state, common CNI data directories, systemd and dbus state,
NetworkManager state, kubelet/containerd state, optional etcd state for
control-plane images, caches, spools, and logs. Extend
`immutable_persistent_paths` when a provider writes additional bootstrap files
after the root filesystem is remounted read-only.

## Validation

Run the focused local checks after changing this target:

```bash
make test-qemu-immutable
make validate-qemu-ubuntu-2404-immutable
```

These checks validate the autoinstall renderer, immutable runtime helper, Packer
target, Packer variable wiring, and Goss contract. They do not replace a
provider-backed Cluster API boot test for the exact artifact format and network
path that will consume the image.

At minimum, provider validation should boot the produced image through Cluster
API, wait for the infrastructure provider machine and CAPI `Machine` readiness
contract, and verify the guest contract over SSH:

```bash
findmnt -no OPTIONS / | tr ',' '\n' | grep -qx ro
test -w /var/lib/cluster-api-data
for path in \
  /etc \
  /home \
  /root \
  /opt/cni/bin \
  /var/cache \
  /var/lib/NetworkManager \
  /var/lib/calico \
  /var/lib/chrony \
  /var/lib/cilium \
  /var/lib/cloud \
  /var/lib/cni \
  /var/lib/containerd \
  /var/lib/dbus \
  /var/lib/etcd \
  /var/lib/kubelet \
  /var/lib/private \
  /var/lib/systemd \
  /var/log \
  /var/spool; do
    test -w "${path}"
done
```

Write sentinels under at least `/etc/kubernetes`, `/home`, and
`/var/lib/kubelet`, reboot the guest, then verify the sentinels are still
present and `/` is still mounted read-only. The same boot test should also
verify that cloud-init finished, `/etc/hostname` contains the provider-assigned
hostname, and `/etc/machine-id` is non-empty after first boot.
