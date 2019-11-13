# Building Images for Azure

This directory contains tooling for building base images for use as nodes in Kubernetes Clusters. [Packer](https://www.packer.io) is used for building these images. This tooling has been forked and extended from the [Wardroom](https://github.com/heptiolabs/wardroom) project.

## Prerequisites

### Prerequisites for all images

- [Packer](https://www.packer.io/intro/getting-started/install.html)
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.8.0

### Prerequisites for Azure

- An Azure account
- The Azure CLI installed and configured
- Set environment variables for `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`

## Building Images

### Building Managed Images in Shared Image Galleries

- Create a resource group, shared image gallery and image definition in the desired correct subscription and location.

For example:

```sh
az group create -n "cluster-api-images" -l southcentralus
az sig create --resource-group cluster-api-images --gallery-name ClusterAPI
az sig image-definition create \
   --resource-group cluster-api-images \
   --gallery-name ClusterAPI \
   --gallery-image-definition capi-ubuntu-1804 \
   --publisher capz \
   --offer capz-demo \
   --sku 18.04-LTS \
   --os-type Linux
```

- From the images/capi directory, run `make build-azure-sig-ubuntu-1804`

### Building VHDs

- Create a resource group and storage account in the desired correct subscription and location.

For example:

```sh
az group create -n "cluster-api-images" -l southcentralus
az storage account create -n "clusterapiimages" -g "cluster-api-images"
```

- From the images/capi directory, run `make build-azure-vhd-ubuntu-1804`
