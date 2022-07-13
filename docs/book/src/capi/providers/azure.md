# Building Images for Azure

These images are designed for use with [Cluster API Provider Azure](https://capz.sigs.k8s.io/introduction.html#what-is-the-cluster-api-provider-azure) (CAPZ). Learn more on using [custom images with CAPZ](https://capz.sigs.k8s.io/topics/custom-images.html).

## Prerequisites for Azure

- An Azure account
- The Azure CLI installed and configured
- Set environment variables for `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`
- Set optional environment variables `RESOURCE_GROUP_NAME`, `STORAGE_ACCOUNT_NAME` & `AZURE_LOCATION` to override the default values

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Azure images are managed by running:

```bash
make deps-azure
```

### Building Managed Images in Shared Image Galleries

From the `images/capi` directory, run `make build-azure-sig-ubuntu-1804`

### Building VHDs

From the `images/capi` directory, run `make build-azure-vhd-ubuntu-1804`

> If building the windows images from a Mac there is a known issue with connectivity. Please see details on running [MacOS with ansible](../windows/windows.md#macos-with-ansible).

### Hyper-V Generation 2 VHDs

Most of the images built from the `images/capi` directory for Azure will be Hyper-V Generation 1 images. There are also a few available configurations to build Generation 2 VMs. The naming pattern is identical to Generation 1 images, with `-gen2` appended to the end of the image name. For example:

```bash
# Generation 1 image
make build-azure-sig-ubuntu-1804

# Generation 2 image
make build-azure-sig-ubuntu-1804-gen2
```

Generation 2 images may only be used with Shared Image Gallery, not VHD.

### Configuration
#### Common Azure options

This table lists several common options that a user may want to set via
`PACKER_VAR_FILES` to customize their build behavior.  This is not an exhaustive
list, and greater explanation can be found in the
[Packer documentation for the Azure ARM builder](https://www.packer.io/docs/builders/azure/arm).

| Variable | Description | Default |
|----------|-------------|---------|
| `private_virtual_network_with_public_ip` | This value allows you to set a virtual_network_name and obtain a public IP. If this value is not set and virtual_network_name is defined Packer is only allowed to be executed from a host on the same subnet / virtual network. | `""` |
| `virtual_network_name` | Use a pre-existing virtual network for the VM. This option enables private communication with the VM, no public IP address is used or provisioned (unless you set private_virtual_network_with_public_ip). | `""` |
| `virtual_network_resource_group_name` | If virtual_network_name is set, this value may also be set. If virtual_network_name is set, and this value is not set the builder attempts to determine the resource group containing the virtual network. If the resource group cannot be found, or it cannot be disambiguated, this value should be set. | `""` |
| `virtual_network_subnet_name` | If virtual_network_name is set, this value may also be set. If virtual_network_name is set, and this value is not set the builder attempts to determine the subnet to use with the virtual network. If the subnet cannot be found, or it cannot be disambiguated, this value should be set. | `""` |

## Developer

If you are adding features to image builder than it is sometimes useful to work with the images directly. This section gives some tips.

### Provision a VM directly from a VHD

After creating a VHD, create a managed image using the url output from `make build-azure-vhd-<image>` and use it to [create the VM](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/build-image-with-packer#create-a-vm-from-the-packer-image): 

```bash
az image create -n testvmimage -g cluster-api-images --os-type <Windows/Linux> --source <storage url for vhd file>
az vm create -n testvm --image testvmimage -g cluster-api-images
```

### Debugging packer scripts
There are several ways to debug packer scripts: https://www.packer.io/docs/other/debugging.html
