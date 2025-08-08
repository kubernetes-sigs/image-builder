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

Modify the `packer/nutanix/nutanix.json` configuration file with credentials and informations specific to your Nutanix Prism Central used to build the image, you can also use the corresponding env variables.
This file have the following format:

```
{

    "nutanix_endpoint": "Prism Central IP / FQDN",
    "nutanix_port": "9440",
    "nutanix_insecure": "false",
    "nutanix_username": "Prism Central Username",
    "nutanix_password": "Prism Central Password",
    "nutanix_cluster_name": "Name of PE Cluster",
    "nutanix_subnet_name": "Name of Subnet"

}
```

Corresponding env variables

`NUTANIX_ENDPOINT`
`NUTANIX_PORT`
`NUTANIX_INSECURE`
`NUTANIX_USERNAME`
`NUTANIX_PASSWORD`
`NUTANIX_CLUSTER_NAME`
`NUTANIX_SUBNET_NAME`


#### Additional options

| Variable              | Description                                                    | Default                             |
|-----------------------|----------------------------------------------------------------|-------------------------------------|
| `force_deregister`    | Allow output image override if already exists.                 | `false`                             |
| `image_delete`        | Delete image once entire build process is completed.           | `false`                             |
| `image_export`        | Export raw image in the current folder.                        | `false`                             |
| `image_name`          | Name of the output image.                                      | `BUILD_NAME-kube-KUBERNETES_SEMVER` |
| `source_image_delete` | Delete source image once build process is completed            | `false`                             |
| `source_image_force`  | Always download and replace source image even if already exist | `false`                             |
| `vm_force_delete`     | Delete the vm even if build is not succesful.                  | `false`                             |

:warning: If you are using a recent `OpenSSH_9` version, adding the `-O` value in `scp_extra_vars` may be necessary for servers that do not implement a recent SFTP protocol.


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

### Output

By default images are stored inside your Nutanix Prism Central Image Library. If you want to use them in different Prism Central or distribute it, you can set the option  `"image_export": "true"` in your build config file.
In this case the images will be downloaded in raw format on the machine where you launch the image-builder process.

## Configuration

The `nutanix` sub-directory inside `images/capi/packer` stores JSON configuration files for each OS including necessary config.

| File                | Description                                   |
|---------------------|-----------------------------------------------|
| `ubuntu-2204.json`  | Settings for Ubuntu 22.04 image               |
| `rockylinux-8.json` | Settings for Rocky Linux 8 image (UEFI)       |
| `rockylinux-9.json` | Settings for Rocky Linux 9 image              |
| `rhel-8.json`       | Settings for RedHat Enterprise Linux 8 image  |
| `rhel-9.json`       | Settings for RedHat Enterprise Linux 9 image  |
| `flatcar.json`      | Settings for Flatcar Linux image (beta)       |
| `windows-2022.json` | Settings for Windows Server 2022 image (beta) |

### OS specific options

#### RHEL

You need to set your `image_url` value correctly in your rhel-(8|9).json file with a working Red Hat Enterprise Linux KVM Guest Image url.

When building the RHEL image, the OS must register itself with the Red Hat Subscription Manager (RHSM). To do this, the current supported method is to supply a username and password via environment variables. The two environment variables are RHSM_USER and RHSM_PASS. Although building RHEL images has been tested via this method, if an error is encountered during the build, the VM is deleted without the machine being unregistered with RHSM. To prevent this, it is recommended to build with the following command:

```
PACKER_FLAGS=-on-error=ask RHSM_USER=user RHSM_PASS=pass make build-nutanix-rhel-9
```

The addition of `PACKER_FLAGS=-on-error=ask` means that if an error is encountered, the build will pause, allowing you to SSH into the machine and unregister manually.
