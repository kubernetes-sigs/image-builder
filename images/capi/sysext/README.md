# systemd-sysext image builds

This directory contains generic helpers for optional system extension images.
Existing CAPI image targets do not use this path yet. Future `*-sysext` targets
can build minimal base images that install only the `systemd-sysext` plumbing
and expect Kubernetes, containerd, CNI, or other payloads to be supplied as
extension images at bootstrap time. `ansible/node-sysext.yml` composes the same
roles as `ansible/node.yml` minus `containerd` and `kubernetes`, so the base
image still gets the common packages, kernel modules, sysctls, and guest agents
that a system extension cannot supply later.

Those future sysext image targets should use `packer/goss/goss-sysext.yaml`
instead of the normal node Goss suite. That test checks the extension
directories and `systemd-sysext` availability, and fails if Kubernetes,
containerd, or CNI payloads are baked into the base image.

To preload sysext images on disk without merging them at boot, stage the `.raw`
files under `/opt/extensions/<name>`. That path is not a systemd-sysext search
path, so the images stay inactive wherever they are staged, regardless of
whether the service is enabled. The `systemd_sysext` role creates that staging
directory alongside the `/etc/extensions` and `/var/lib/extensions` search
paths, following the layout the `gpu` role already uses for the Flatcar NVIDIA
runtime extension. Passing `systemd_sysext_enable_service=false` through
`ansible_user_vars` is a separate switch: it leaves `systemd-sysext.service`
disabled, so images placed in a search path later are not merged either.

System extension images are limited to `/usr` and `/opt`. Configuration,
mutable state, service enablement, kernel/firmware content, and bootloader
changes must stay in the base image, bootstrap data, or a future
`systemd-confext` path.

Build a layer from a prepared rootfs:

```bash
images/capi/sysext/build-sysext-layer.sh \
  --name kubernetes \
  --version v1.34.0 \
  --rootfs /path/to/rootfs \
  --output-dir out/sysext \
  --os-id ubuntu \
  --os-version 24.04
```

Image contents are always owned by uid 0 and gid 0, whoever runs the build.
`mke2fs -d` otherwise preserves the ownership of the source tree, which would
leave a merged `/usr` owned by the build user. The payload is therefore packed
into a tar archive with numeric owner 0, extended attributes included, and that
archive is handed to `mke2fs` directly where `mke2fs` was built with libarchive
(e2fsprogs 1.47.1 and later, and only when that build option is on). Where it
was not, the same archive is extracted as root and the resulting tree is passed
to `mke2fs`. Running unprivileged without libarchive support fails rather than
writing an image with the wrong ownership. Both paths go through one archive so
that file capabilities and other extended attributes survive; chowning a copy
would clear them.

Image sizing is derived from the payload. `SYSEXT_OVERHEAD_PERCENT` (default
`25`) is the block headroom added on top of the payload and the margin on the
inode count, `SYSEXT_MIN_OVERHEAD_KIB` (default `16384`) is the block headroom
floor, and `SYSEXT_MIN_INODES` (default `1024`) is the inode floor. The inode
count is set explicitly because `mke2fs` otherwise derives it from the image
size, which runs out on payloads made of many small files.

`make test-sysext` runs the helper's smoke test. It is part of `make
validate-all` and skips itself when `mke2fs` or `debugfs` is missing, or when
the host can neither pass a tar stream to `mke2fs` nor run as root.

The rootfs must contain only `usr/` and `opt/`. If
`usr/lib/extension-release.d/extension-release.<raw-image-basename>` is
missing, the helper creates one from the supplied OS, version, and architecture
fields. `--os-id` and `--os-version` are required and must match the target
host's `/usr/lib/os-release` `ID` and `VERSION_ID` (for example `ubuntu`/`24.04`
or `flatcar`/`4152.2.0`); systemd-sysext refuses to merge the image at runtime
otherwise. The metadata filename must match the sysext image basename, for
example `extension-release.kubernetes-v1.34.0-x86-64` for
`kubernetes-v1.34.0-x86-64.raw`.
