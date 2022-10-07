# Building Images on OpenStack

## Hypervisor

The image is built using Openstack.

### Prerequisites for Openstack builds

Execute the following command to install the Openstack client.
```bash
# pip install python-openstackclient
```
Alternatively, you can [download and install the tarball](https://docs.openstack.org/python-openstackclient/latest/#getting-started).


Also ensure you have a [Ubuntu 20.04](https://cloud-images.ubuntu.com/focal/current/) or [Ubuntu 22.04](https://cloud-images.ubuntu.com/jammy/current/) cloud image available in your Openstack instance before continuing as it will need to be referenced.

#### Note
> Other OS's will be supported at a later time.

## Setup Openstack authentication
Ensure you have set up your method of authentication ([examples here](https://docs.openstack.org/python-openstackclient/zed/cli/authentication.html)).
You can set environment variables via the RC file from your Openstack cluster or use the clouds.yaml approach by setting the OS_CLOUD environment variable.
You should be able to run commands against openstack before running this builder otherwise it will fail.

You can test with a simple command such as `openstack image list`. It should show a list of images available.


## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Openstack images are managed by running:

```bash
cd image-builder/images/capi
make deps-openstack
```


### Define variables for Openstack build
Using the [Openstack packer provider](https://developer.hashicorp.com/packer/plugins/builders/openstack), an instance will be deployed and an image built from it.
A certain set of environment variables (example below) must be defined in a josn file  and reference it during `make build-openstack-ubuntu-xxxx`. Please replace xxxx with 2004 or 2204.

Replace UPPERCASE variables with your values.
```json
{
  "source_image": "OPENSTACK_SOURCE_IMAGE_ID",
  "networks": "OPENSTACK_NETWORK_ID",
  "flavor": "OPENSTACK_INSTANCE_FLAVOR_NAME",
  "floating_ip_network": "OPENSTACK_FLOATING_IP_NETWORK_NAME"
}
```

#### Note:
> The following Kuberentes versions have been tested: 1.23.10, 1.24.7 and 1.25.3. <br>
The following crictl versions have been tested: 1.23.0, 1.24.0 and 1.25.0.

Check out `images/capi/packer/openstack/packer.json` for more variables such as allowing the use of floating IPs and config drives.

### Building Image on Openstack

From the `images/capi` directory, run `PACKER_VAR_FILES=var_file.json make build-openstack-ubuntu-xxxx`.

An instance is built in Openstack from the source image defined and once completed, the instance is shutdown and the volume uploaded into an image that can then be used.
This image will default to private and will need to be set as shared or public to be used by other projects within Openstack.

For building a ubuntu-2204 based capi image with Kubernetes 1.25.3, run the following commands:

#### Example
```bash
$ git clone https://github.com/kubernetes-sigs/image-builder.git
$ cd image-builder/images/capi/
$ make deps-openstack
$ make build-openstack-ubuntu-2204
```

The resulting image will be named `ubuntu-2204-kube-v1.25.3` based on the following format: `ubuntu-XXXX-kube-KUBERNETES_SEMVER`.

This can be modified by overriding the `image_name` variable if required.