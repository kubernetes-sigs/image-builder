# Custom build targets

Image Builder creates CAPI images through Make targets in `images/capi/Makefile`.
Most targets are generated from provider-specific name lists. The target name
selects the provider recipe and the Packer variable file for the operating
system.

For example, `make build-qemu-ubuntu-2404` uses:

- the `qemu` provider recipe from `packer/qemu/packer.json`
- the target-specific variables from `packer/qemu/qemu-ubuntu-2404.json`
- the common Linux node variables from `packer/config/*.json`

The matching `make validate-qemu-ubuntu-2404` target validates the same Packer
configuration without building the image.

`PACKER_VAR_FILES` can override variables for an existing target, but it does
not create a new Make target or choose a different provider recipe. Add a target
name when you need a new provider and OS combination.

## Create a local-only target

Use this when you need to keep building an operating system version that Image
Builder no longer supports by default, or when you need a private provider and
OS combination.

1. Pick the closest existing provider and OS target.
2. Copy the provider's target-specific Packer variable file.
3. Update the copied file for your base image, distribution metadata, ISO,
   cloud image, or provider image identifiers.
4. Override the provider build-name list for the `make` invocation.
5. Validate the target before building it.

For example, to keep a local QEMU target based on the Ubuntu QEMU layout:

```sh
cd images/capi
cp packer/qemu/qemu-ubuntu-2404.json packer/qemu/qemu-ubuntu-2004.json

make QEMU_BUILD_NAMES="qemu-ubuntu-2004" validate-qemu-ubuntu-2004
make QEMU_BUILD_NAMES="qemu-ubuntu-2004" build-qemu-ubuntu-2004
```

Command-line values replace the default list for that invocation. If you want an
`*-all` target to include both the default targets and your custom one, pass the
full list you want to build.

Keep these local target files in your own fork or downstream branch if the
target is not supported by upstream Image Builder.

## Add an upstream target

Use this for a provider and OS combination that should be maintained by Image
Builder.

1. Add the target-specific Packer variable file under the provider directory in
   `images/capi/packer`. Reuse the nearest supported OS file as a starting
   point.
2. Add the target name to the provider list in `images/capi/Makefile`, or to the
   shared OS version list used by that provider.
3. Add static build and validate help entries in the "Document dynamic build
   targets" and "Document dynamic validate targets" sections of
   `images/capi/Makefile` so `make help` shows the new target.
4. Update the provider documentation when users need new credentials, cloud
   image identifiers, or provider-specific variables.
5. Run the matching `validate-*` target. Run a real `build-*` target when the
   provider can be exercised locally or in CI.

For example, a new QEMU target named `qemu-example-linux-9` would usually need:

- `images/capi/packer/qemu/qemu-example-linux-9.json`
- `qemu-example-linux-9` in `QEMU_BUILD_NAMES`
- `build-qemu-example-linux-9` and `validate-qemu-example-linux-9` help entries

## Target name reference

The provider list determines which dynamic targets exist. Most providers derive
their Packer variable file from the target name after removing `build-` or
`validate-`.

| Provider target form | Build-name list | Target-specific variable file |
| --- | --- | --- |
| `build-ami-<os>` | `AMI_BUILD_NAMES` | `packer/ami/<os>.json` |
| `build-azure-sig-<os>` | `azure_targets.sh` | `packer/azure/<os>.json` |
| `build-do-<os>` | `DO_BUILD_NAMES` | `packer/digitalocean/<os>.json` |
| `build-gce-<os>` | `GCE_BUILD_NAMES` | `packer/gce/<os>.json` |
| `build-hcloud-<os>` | `HCLOUD_BUILD_NAMES` | `packer/hcloud/<os>.json` |
| `build-nutanix-<os>` | `NUTANIX_BUILD_NAMES` | `packer/nutanix/<os>.json` |
| `build-openstack-<os>` | `OPENSTACK_BUILD_NAMES` | `packer/openstack/<os>.json` |
| `build-oci-<os>` | `OCI_BUILD_NAMES` | `packer/oci/<os>.json` |
| `build-osc-<os>` | `OSC_BUILD_NAMES` | `packer/outscale/<os>.json` |
| `build-proxmox-<os>` | `PROXMOX_BUILD_NAMES` | `packer/proxmox/<os>.json` |
| `build-qemu-<os>` | `QEMU_BUILD_NAMES` | `packer/qemu/qemu-<os>.json` |
| `build-raw-<os>` | `RAW_BUILD_NAMES` | `packer/raw/raw-<os>.json` |
| `build-scaleway-<os>` | `SCALEWAY_BUILD_NAMES` | `packer/scaleway/<os>.json` |
| `build-vultr-<os>` | `VULTR_BUILD_NAMES` | `packer/vultr/<os>.json` |
| `build-node-ova-local-<os>` | `PLATFORMS_AND_VERSIONS` | `packer/ova/<os>.json` |
| `build-node-ova-vsphere-<os>` | `PLATFORMS_AND_VERSIONS` | `packer/ova/<os>.json` |

Provider recipes can have extra shared files. For example, Azure SIG targets
also use `packer/azure/azure-config.json` and the SIG variant file, while OVA
targets use `packer/ova/packer-common.json`. Check the existing recipe for the
provider you are extending before adding a new target.
