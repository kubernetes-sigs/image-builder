## Custom Kubernetes version

To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

```
PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make build-proxmox-ubuntu-2204
```

## ISO files

To use existing ISO files, set the `ISO_FILE` environment variable to the path of the ISO file.
For example, to use a local ISO file, set the `ISO_FILE` environment variable like this:

```
export ISO_FILE="local:iso/ubuntu-24.04.2-live-server-amd64.iso"
```

## Flatcar for Proxmox

Proxmox support is available on Flatcar from version `4152`.
* https://www.flatcar.org/releases#alpha-release
* https://github.com/coreos/fedora-coreos-tracker/issues/1652

Therefore, we need to choose the right channel and version for flatcar along with `OEM_ID=proxmoxve`.

**To build a Proxmox template for flatcar**

```shell
export PROXMOX_URL="https://example.net:8006/api2/json"
export PROXMOX_USERNAME='root@pam!proxmox'
export PROXMOX_TOKEN="xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxxxxxx"
export PROXMOX_NODE="pve1"
export PROXMOX_ISO_POOL="local"
export PROXMOX_BRIDGE="vmbr1"
export PROXMOX_STORAGE_POOL="ceph_pool"
