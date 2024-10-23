## Custom Kubernetes version

To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

```
PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make build-proxmox-ubuntu-2204
```

## ISO files

To use existing ISO files, set the `ISO_FILE` environment variable to the path of the ISO file.
For example, to use a local ISO file, set the `ISO_FILE` environment variable like this:

```
export ISO_FILE="local:iso/ubuntu-24.04.1-live-server-amd64.iso"
```

## Flatcar for Proxmox

Currently, Proxmox doesn't support ignition and it's currently in-development.
* https://github.com/coreos/fedora-coreos-tracker/issues/1652
* https://github.com/flatcar/scripts/pull/1783

But we do a trick to make it working on Proxmox, until the support is already released.

We use OEM_ID `nutanix` which is an openstack provider that loads ignition from device with label `config-2`:
https://github.com/coreos/ignition/blob/main/internal/providers/nutanix/nutanix.go#L51

Therefore, we build an image with `OEM_ID=nutanix` so that we can provide an ISO that contain the ignition file in `/openstack/latest/user_data`
https://github.com/coreos/ignition/blob/main/internal/providers/nutanix/nutanix.go#L40C29-L40C56

**To build a Proxmox template for flatcar**

```shell
export PROXMOX_URL="https://example.net:8006/api2/json"
export PROXMOX_USERNAME='root@pam!proxmox'
export PROXMOX_TOKEN="xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxxxxxx"
export PROXMOX_NODE="pve1"
export PROXMOX_ISO_POOL="local"
export PROXMOX_BRIDGE="vmbr1"
export PROXMOX_STORAGE_POOL="ceph_pool"

## flatcar version
export FLATCAR_VERSION=4081.1.0
export FLATCAR_CHANNEL=beta

export OEM_ID=nutanix # make sure to choose OEM_ID=nutanix
```
