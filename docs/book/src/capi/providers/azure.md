# Building Images for Azure

## Prerequisites

The `make deps-azure` target will test that Ansible, Packer, and `jq` are installed and available. If they are not, they will be installed to `images/capi/.bin`. This directory will need to be added to your `$PATH`.

### Prerequisites for all images

- [Packer](https://www.packer.io/intro/getting-started/install.html)
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.8.0

### Prerequisites for Azure

- An Azure account
- The Azure CLI installed and configured
- Set environment variables for `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`

## Building Images

### Building Managed Images in Shared Image Galleries

From the `images/capi` directory, run `make build-azure-sig-ubuntu-1804`

### Building VHDs

From the `images/capi` directory, run `make build-azure-vhd-ubuntu-1804`
