# Building Images for OpenStack

## Hypervisor

The image is built using the following environments:

| Environment | Builder   | Build target       |
|-------------|-----------|--------------------|
| KVM         | QEMU      | build-qemu-ubuntu- |
| OpenStack   | OpenStack | build-openstack    |

### Prerequisites for QEMU Builder

#### Installing packages to use qemu-img

Execute the following command to install qemu-kvm and other packages if you are running Ubuntu 18.04 LTS.

```bash
$ sudo -i
# apt install qemu-kvm libvirt-bin qemu-utils
```

If you're on Ubuntu 20.04 LTS, then execute the following command to install qemu-kvm packages.

```bash
$ sudo -i
# apt install qemu-kvm libvirt-daemon-system libvirt-clients virtinst cpu-checker libguestfs-tools libosinfo-bin
```

#### Adding your user to the kvm group

```bash
$ sudo usermod -a -G kvm <yourusername>
$ sudo chown root:kvm /dev/kvm
```

Then exit and log back in to make the change take place.

### Prerequisites for OpenStack Builder

Complete the `images/capi/packer/qemu/openstack.json` configuration file with credentials and informations specific to the remote OpenStack environment.
Please refer to the [Packer documentation for the OpenStack Builder](https://www.packer.io/docs/builders/openstack) for each variables.

## Building Images

### Building Images using QEMU Builder

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for building images are managed by running:

```bash
make deps-qemu
```

From the `images/capi` directory, run `make build-qemu-ubuntu-xxxx`. The image is built and located in `images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION`. Please replace xxxx with `1804` or `2004` depending on the version you want to build the image for.

### Building Images using OpenStack Builder

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for building images are managed by running:

```bash
make deps-openstack
```

From the `images/capi` directory, run `make build-openstack`. The images is built in the remote OpenStack environment with the name `BUILD_NAME+kube-KUBERNETES_VERSION`.
