# Building Raw Images (Baremetal)

## Hypervisor

The image is built using KVM hypervisor.

### Prerequisites for QCOW2

Execute the following command to install qemu-kvm and other packages if you are running Ubuntu 18.04 LTS.

#### Installing packages to use qemu-img

```bash
$ sudo -i
# apt install qemu-kvm libvirt-bin qemu-utils
```

#### Adding your user to the kvm group

```bash
$ sudo usermod -a -G kvm <yourusername>
$ sudo chown root:kvm /dev/kvm
```

Then exit and log back in to make the change take place.

## Raw Images
### Raw Dependencies

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building raw images are managed by running:

```bash
cd image-builder/images/capi
make deps-raw
```
### Build the Raw Image

From the `images/capi` directory, run `make build-raw-ubuntu-xxxx`. The image is built and located in images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION. Please replace xxxx with `2004` or `2004-efi` depending on the version you want to build the image for.

To build a Ubuntu 24.04-based CAPI image, run the following commands -

```bash
$ git clone https://github.com/kubernetes-sigs/image-builder.git
$ cd image-builder/images/capi/
$ make build-raw-ubuntu-2404
```

## QCOW2 Images
### Raw Dependencies

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building raw images are managed by running:

```bash
cd image-builder/images/capi
make deps-qemu
```

### Building QCOW2 Image

From the `images/capi` directory, run `make build-qemu-ubuntu-xxxx`. The image is built and located in images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION. Please replace xxxx with `1804`,`2004` or `2204` depending on the version you want to build the image for.

For building a ubuntu-2204 based CAPI image, run the following commands -

```bash
$ git clone https://github.com/kubernetes-sigs/image-builder.git
$ cd image-builder/images/capi/
$ make build-qemu-ubuntu-2204
```
