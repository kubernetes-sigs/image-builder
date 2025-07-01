# Building Images on OpenStack

## Hypervisor

The image is built using OpenStack.

### Prerequisites for OpenStack builds

First, check for prerequisites at [Packer docs for the OpenStack builder](https://developer.hashicorp.com/packer/plugins/builders/openstack).

Also ensure that you have a [Ubuntu 24.04](https://cloud-images.ubuntu.com/noble/current/) or [Ubuntu 22.04](https://cloud-images.ubuntu.com/jammy/current/) cloud image available in your OpenStack instance before continuing as it will need to be referenced.
This build process also supports Flatcar Linux, but only Stable has been tested.

#### Note
> Other operating systems could be supported and additions are welcome.

## Setup Openstack authentication
Ensure you have set up your method of authentication. See the [examples here](https://docs.openstack.org/python-openstackclient/zed/cli/authentication.html).
You can also check out the [packer builder](https://developer.hashicorp.com/packer/plugins/builders/openstack#configuration-reference) for more information on authentication.

You should be able to run commands against OpenStack before running this builder, otherwise it will fail.
You can test with a simple command such as `openstack image list`.

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building OpenStack images are managed by running:

```bash
cd image-builder/images/capi
make deps-openstack
```

### Define variables for OpenStack build

Using the [Openstack packer provider](https://developer.hashicorp.com/packer/plugins/builders/openstack), an instance will be deployed and an image built from it.
A certain set of environment variables must be defined in a json file and referenced as shown below in the build example.

Replace UPPERCASE variables with your values.
```json
{
  "source_image": "OPENSTACK_SOURCE_IMAGE_ID",
  "networks": "OPENSTACK_NETWORK_ID",
  "flavor": "OPENSTACK_INSTANCE_FLAVOR_NAME",
  "floating_ip_network": "OPENSTACK_FLOATING_IP_NETWORK_NAME",
  "image_name": "KUBE-UBUNTU",
  "image_visibility": "public",
  "image_disk_format": "raw",
  "volume_type": "",
  "ssh_username": "ubuntu"
}
```

Check out `images/capi/packer/openstack/packer.json` for more variables such as allowing the use of floating IPs and config drives.

### Building Image on OpenStack

From the `images/capi` directory, run `PACKER_VAR_FILES=var_file.json make build-openstack-<DISTRO>`.

An instance is built in OpenStack from the source image defined. Once completed, the instance is shut down and the image is created.
This image will default to private, however this can be controlled via `image_visibility`.

For building a ubuntu 22.04-based CAPI image with Kubernetes 1.23.15, run the following commands:

#### Example
```bash
$ git clone https://github.com/kubernetes-sigs/image-builder.git
$ cd image-builder/images/capi/
$ make deps-openstack
$ PACKER_VAR_FILES=var_file.json make build-openstack-ubuntu-2204
```

The resulting image will be named `ubuntu-2204-kube-v1.23.15` based on the following format: `<OS>-kube-<KUBERNETES_SEMVER>`.

This can be modified by overriding the `image_name` variable if required.
