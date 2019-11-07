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

From the images/capi directory, run `make build-azure-sig-ubuntu-1804`

### Building VHDs

From the images/capi directory, run `make build-azure-vhd-ubuntu-1804`
