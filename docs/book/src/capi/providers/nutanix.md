# Building CAPI Images for Nutanix Cloud Platform

## Prerequisites for Nutanix builder

```bash
# If you don't have the image-builder repository
$ git clone https://github.com/kubernetes-sigs/image-builder.git

$ cd image-builder/images/capi/
# Run the target make deps-nutanix to install Ansible and Packer
$ make deps-nutanix
```

## Configure the Nutanix builder

Complete the `packer/nutanix/nutanix.json` configuration file with credentials and informations specific to the Nutanix Prism Central used to build the image.
This file must have the following format:
```
{
    "force_deregister": "true",
    "nutanix_cluster_name": "Name of PE Cluster",
    "nutanix_endpoint": "Prism Central IP / FQDN",
    "nutanix_insecure": "false",
    "nutanix_password": "PrismCentral_Password",
    "nutanix_port": "9440",
    "nutanix_subnet_name": "Name of Subnet",
    "nutanix_username": "PrismCentral_Username",
    "scp_extra_vars": ""
}
```

If you are using a recent `OpenSSH_9` version, adding the `-O` value in `scp_extra_vars` may be necessary for servers that do not implement a recent SFTP protocol.

## Customizing the Build Process

The builder uses a generic cloud image as source which is basically configured by a cloud-init script.
It is also possible to start build-process from an ISO-Image as long as injecting Kickstart or similiar is possible via OEMDRV Media.
For more details refer to packer-plugin-nutanix Documentation.

If you prefer to use a different configuration file, you can create it with the same format and export `PACKER_VAR_FILES` environment variable containing the full path to it.
## Run the Make target to generate Nutanix images.
From `images/capi` directory, run `make build-nutanix-<os>-<version>` command depending on which os and version you want to build the image for.

For example, to build an image for `Ubuntu 22.04`, run
```bash
$ make build-nutanix-ubuntu-2204
```

To build all Nutanix ubuntu images, run

```bash
make build-nutanix-all
```

## Configuration

The `nutanix` sub-directory inside `images/capi/packer` stores JSON configuration files for each OS including necessary config.

| File                | Description                                   |
|---------------------|-----------------------------------------------|
| `ubuntu-2004.json`  | Settings for Ubuntu 20.04 image               |
| `ubuntu-2204.json`  | Settings for Ubuntu 22.04 image               |
| `rockylinux-8.json` | Settings for Rocky Linux 8 image (UEFI)       |
| `rockylinux-9.json` | Settings for Rocky Linux 9 image              |
| `flatcar.json`      | Settings for Flatcar Linux image (beta)       |
| `windows-2022.json` | Settings for Windows Server 2022 image (beta) |
