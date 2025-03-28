# Building Images for Proxmox VE

## Prerequisites

- A Proxmox cluster
- Set environment variables for `PROXMOX_URL`, `PROXMOX_USERNAME`, `PROXMOX_TOKEN`, `PROXMOX_NODE`
- Set optional environment variables `PROXMOX_ISO_POOL`, `PROXMOX_BRIDGE`, `PROXMOX_STORAGE_POOL` to override the default values

## Networking Requirements

The image build process expects a few things to be in place before the build process will complete successfully.

1. DHCP must be available to assign the packer VM an IP
  * The packer proxmox integration currently does not support the ability to assign static IPs, thus DHCP is required.
  * Access to internet hosts is optional, but the VM will not be able to apply any current updates and will need to be manually rebooted to get a clean cloud-init status.
2. The build VM must be accessible via SSH from the host running `make build-proxmox...`
3. The build VM must have DHCP, DNS, HTTP, HTTPS and NTP accessibility to successfully update the OS packages.

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Proxmox VM templates are managed by running the following command from images/capi directory.

```bash
make deps-proxmox
```

From the `images/capi` directory, run `make build-proxmox-<OS>` where `<OS>` is
the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `proxmox`
directory includes several JSON files that define the default configuration for
the different operating systems.

| File               | Description                             |
|--------------------|-----------------------------------------|
| `ubuntu-2204.json` | The settings for the Ubuntu 22.04 image |
| `ubuntu-2404.json` | The settings for the Ubuntu 24.04 image |

The full list of available environment vars can be found in the `variables` section of `images/capi/packer/proxmox/packer.json`.

Each variable in this section can also be overridden via the `PACKER_FLAGS` environment var.

```bash
export PACKER_FLAGS="--var 'kubernetes_rpm_version=1.29.6' --var 'kubernetes_semver=v1.29.6' --var 'kubernetes_series=v1.29' --var 'kubernetes_deb_version=1.29.6-1.1'"
make build-proxmox-ubuntu-2204
```

If different packages are desired then find the available dep packages [here](https://build.opensuse.org/package/revisions/isv:kubernetes:core:shared:build/kubernetes-cni) 
and [here](https://build.opensuse.org/project/show/isv:kubernetes:core:stable).

If using a proxmox API token the format of the PROXMOX_USERNAME and PROXMOX_TOKEN must look like so:

| PROXMOX_USERNAME              | PROXMOX_TOKEN  |
|-------------------------------|----------------|
| <username>@<realm>!<token_id> | <token secret> |

For example:

| PROXMOX_USERNAME       | PROXMOX_TOKEN                        |
|------------------------|--------------------------------------|
| image-builder@pve!capi | 9db7ce4e-4c7f-46ed-8ab4-3c8e98e88c7e |

Then the user (not token) must be given the following permissions on the path `/` and propagated:

* Datastore.*
* SDN.*
* Sys.AccessNetwork
* Sys.Audit
* VM.*

*We suggest creating a new role, since no built-in PVE roles covers just these.*

Note that you might have to change disk format from `qcow2` to `raw` using the `disk_format` packer flag if the storage for the VM disk is block only (see the note below).

### Building images for Flatcar

The default metadata source for Flatcar is set to `proxmoxve` (userdata via config drive). If you need to set a [different OEM](https://coreos.github.io/ignition/supported-platforms/) you need to overwrite packer flag `oem_id`, e.g. 

```bash
export PACKER_FLAGS="--var 'oem_id=qemu'"
make build-proxmox-flatcar
```

### Example

Prior to building images you need to ensure you have set the required environment variables:

```bash
export PROXMOX_URL="https://pve.example.com:8006/api2/json"
export PROXMOX_USERNAME=<USERNAME>
export PROXMOX_TOKEN=<TOKEN_ID>
export PROXMOX_NODE="pve"
export PROXMOX_ISO_POOL="local"
export PROXMOX_BRIDGE="vmbr0"
export PROXMOX_STORAGE_POOL="local-lvm"
```

- Build ubuntu 2204 template:

```bash
make build-proxmox-ubuntu-2204
```

### Note on disk formats

Depending on what storage type you are using, you will need to change the default disk
format from `qcow2` to something else.
Go to [Proxmox Storage Documentation](https://pve.proxmox.com/wiki/Storage#_see_also) and
look into the documentation of the storage type backing your selected storage pool to see which
disk formats are supported. If the storage type does not list `qcow2` in in the supported
image formats, you will need to change the packer variable `disk_format` to a supported format.

For example when using the ZFS storage type, which does not support `qcow2`, you can use the
`raw` disk format.

```sh
export PROXMOX_STORAGE_POOL="local-zfs" PACKER_FLAGS="-var disk_format=raw"
```
