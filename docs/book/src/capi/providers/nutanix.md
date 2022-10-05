# Building CAPI Images for Nutanix Cloud Platform (NCP)

## Install Ansible and Packer

```bash
# If you dont have the image-builder repository
$ git clone https://github.com/kubernetes-sigs/image-builder.git

$ cd image-builder/images/capi/
# Run the target make deps-nutanix to install ansible and packer
$ make deps-nutanix
```
## Prerequisites for Nutanix builder

Complete the `packer/nutanix/nutanix.json` configuration file with credentials and informations specific to the Nutanix Prism Central used to build the image.
This file must have the following format:
```
{
    "nutanix_cluster_name": "Name of PE Cluster",
    "source_image_name": "Name of Source Image/ISO",
    "image_name": "Name of Destination Image",
    "nutanix_subnet_name": "Name of Subnet",
    "nutanix_endpoint": "Prism Central IP / FQDN",
    "nutanix_insecure": "false",
    "nutanix_port": "9440",
    "nutanix_username": "PrismCentral_Username",
    "nutanix_password": "PrismCentral_Password",
}
```

## Customizing the Build Process

The builder uses a generic cloud image as source which is basically configured by a cloud-init script.
It is also possible to start build-process from an ISO-Image as long as injecting Kickstart or similiar is possible via OEMDRV Media.
For more details refer to packer-plugin-nutanix Documentation.

If you prefer to use a different configuration file, you can create it with the same format and export `PACKER_VAR_FILES` environment variable containing the full path to it.
## Run the Make target to generate Nutanix images.
From `images/capi` directory, run `make build-nutanix-ubuntu-<version>` command depending on which ubuntu version you want to build the image for.

For instance, to build an image for `ubuntu 20-04`, run
```bash
$ make build-nutanix-ubuntu-2004
```

To build all Nutanix ubuntu images, run

```bash
make build-nutanix-all
```

## Configuration

The `nutanix` sub-directory inside `images/capi/packer` stores JSON configuration files for Ubuntu OS including necessary cloud-init.

| File | Description
| -------- | --------
| `ubuntu-2004.json`     | Settings for Ubuntu 20-04 image     |