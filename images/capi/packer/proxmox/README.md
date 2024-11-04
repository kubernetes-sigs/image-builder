To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

```
PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make build-proxmox-ubuntu-2204
```


# ISO files

To use existing ISO files, set the `ISO_FILE` environment variable to the path of the ISO file.
For example, to use a local ISO file, set the `ISO_FILE` environment variable like this:

```
export ISO_FILE="local:iso/ubuntu-24.04.1-live-server-amd64.iso"
```
