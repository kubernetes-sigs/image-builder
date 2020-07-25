# Building Images for OpenStack

## Hypervisor

The image is built using KVM hypervisor.

### Prerequisites for QCOW2

This section assumes Ubuntu 18.04 LTS.

#### Installing packages to use qemu-img

```bash
# apt install qemu-kvm libvirt-bin qemu-utils
```

#### Adding your user to the kvm group

```bash
$ sudo usermod -a -G kvm <yourusername>
$ sudo chown root:kvm /dev/kvm
```

Then exit and log back in to make the change take place.

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building qemu images are managed by running:

```bash
make deps-qemu
```

### Building QCOW2 Image

From the `images/capi` directory, run `make build-qemu-ubuntu-1804`. The image is built and located in `images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION`.
