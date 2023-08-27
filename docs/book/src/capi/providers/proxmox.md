# Building Images for Proxmox VE

## Prerequisites

- A Proxmox cluster
- Set environment variables for `PROXMOX_URL`, `PROXMOX_USERNAME`, `PROXMOX_TOKEN`, `PROXMOX_NODE`
- Set optional environment variables `PROXMOX_ISO_POOL`, `PROXMOX_BRIDGE`, `PROXMOX_STORAGE_POOL` to override the default values

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

### Example

Prior to building images you need to ensure you have set the required environment variables:

```
export PROXMOX_URL="https://pve.example.com:8006/api2/json"
export PROXMOX_USERNAME=<USERNAME>
export PROXMOX_TOKEN=<TOKEN_ID>
export PROXMOX_NODE="pve"
export PROXMOX_ISO_POOL="local"
export PROXMOX_BRIDGE="vmbr0"
export PROXMOX_STORAGE_POOL="local-lvm"
```

Build ubuntu 2204 template:

```
make build-proxmox-ubuntu-2204
```
