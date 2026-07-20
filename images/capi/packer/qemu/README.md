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
- `immutable_data_partition_mount=/.capi-data`: mount point for persistent runtime data.
- `immutable_data_partition_mount_options=defaults,x-systemd.device-timeout=30s`: fstab options for the required data partition.
- `immutable_root_partition_size=12884901888`: root partition size in bytes; the data partition uses the remaining disk.
- `immutable_read_only_root=true`: write `/` as read-only in `/etc/fstab` for the final image.
- `immutable_persistent_paths=/etc,/home,/root,/mnt,/media,/opt,/srv,/usr/local,/var/backups,/var/cache,/var/crash,/var/lib,/var/local,/var/log,/var/mail,/var/opt,/var/spool`: copy existing contents into the data partition and bind mount them back for CAPI bootstrap and node runtime writes.
- `immutable_tmpfs_paths=/tmp,/var/tmp`: mount volatile scratch paths as tmpfs.

The persistent path list is intentionally explicit. It covers first-boot
configuration under `/etc`, user home directories, SSH host keys, `/mnt`,
`/media`, `/opt`, `/usr/local`, `/srv`, and the common mutable `/var` subtrees
used by package state, cloud-init, kubelet, containerd, CNI, systemd, dbus,
NetworkManager, control-plane etcd data, caches, crash dumps, spools, and logs.
The data partition is mounted outside `/var` so `/var/lib` can be persistent as a whole.
Providers that write additional bootstrap files should extend
`immutable_persistent_paths` rather than making the whole root writable again.
The data partition and bind mounts are required mounts. Do not add `nofail`
unless the image target has a separate recovery path for missing writable
runtime storage. The immutable runtime step writes systemd drop-ins so
cloud-init, containerd, kubelet, and SSH wait for the writable mounts.

The default QEMU disk is 20 GiB and `immutable_root_partition_size` reserves
12 GiB for the read-only root. The data partition receives the remaining disk
space, which must be large enough for `/var/lib/containerd`, kubelet state,
logs, and bootstrap data. Increase `disk_size` when the workload or provider
needs more writable runtime capacity.

The target validates the contract in four places:

- the Ubuntu autoinstall renderer unit tests verify root/data partition
  rendering and input validation;
- the immutable runtime unit tests verify fstab replacement, persistent bind
  mount generation, top-level directory metadata preservation, systemd mount
  ordering, content copy, tmpfs generation, and the data-partition requirement
  for persistent paths;
- `packer validate` verifies the QEMU target, Packer variables, and Goss
  variable wiring;
- Goss runs after immutable runtime configuration and verifies the labeled data
  partition, writable data mount, writable persistent bind mounts, writable
  tmpfs paths, service mount-ordering drop-ins, and read-only root fstab entry.

Run the focused immutable validation with:

```bash
make test-qemu-immutable
make validate-qemu-ubuntu-2404-immutable
```

These checks prove the image build contract. They do not replace a provider
boot test, because the risky immutable-image path is first boot plus bootstrap
writes after `/` is remounted read-only.

### CAPI and boot validation

After building the image, run one provider-backed Cluster API validation for the
exact artifact and network path that will consume it. At minimum the validation
should:

1. Serve or upload the produced image in the format consumed by the provider
   (`format=raw` for providers that boot raw disk images, `format=qcow2` for
   providers that boot qcow2).
2. Create a Cluster API workload cluster using the provider image reference.
3. Wait until the provider machine reports a provisioned or ready state.
4. Wait until the CAPI `Machine` has `BootstrapConfigReady=True`,
   `InfrastructureReady=True`, a non-empty `spec.providerID` or
   `status.providerID`, and, for full cluster bootstrap tests, a workload
   `status.nodeRef`.
5. SSH into the booted guest and verify:

   ```bash
   findmnt -no OPTIONS / | tr ',' '\n' | grep -qx ro
   test -w /.capi-data
   for path in \
     /etc \
     /home \
     /root \
     /mnt \
     /media \
     /opt \
     /srv \
     /usr/local \
     /var/backups \
     /var/cache \
     /var/crash \
     /var/lib \
     /var/local \
     /var/log \
     /var/mail \
     /var/opt \
     /var/spool; do
       test -w "${path}"
   done
   ```

6. Write sentinels under at least `/etc/kubernetes`, `/home`, and
   `/var/lib/kubelet`,
   reboot the guest, then verify the sentinels are still present and `/` is
   still mounted read-only. The same boot test should verify that cloud-init
   finished, `/etc/hostname` contains the provider-assigned hostname, and
   `/etc/machine-id` is non-empty after first boot.

For a local pre-CAPI boot smoke, boot the produced artifact with QEMU and a
temporary NoCloud seed. The smoke should use the same checks as above, plus a
reboot/persistence check, before the image is promoted to provider CAPI tests.
