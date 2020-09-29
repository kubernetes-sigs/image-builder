# Building Images for Azure

These images are designed for use with [Cluster API Provider Azure]([Cluster API Provider Azure](https://capz.sigs.k8s.io/introduction.html#what-is-the-cluster-api-provider-azure)) (CAPZ). Learn more on using [custom images with CAPZ](https://capz.sigs.k8s.io/topics/custom-images.html).

## Prerequisites for Azure

- An Azure account
- The Azure CLI installed and configured
- Set environment variables for `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`

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