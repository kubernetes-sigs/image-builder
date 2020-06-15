# Building Images for OpenStack

## Prerequisites

The `make deps-qemu` target will test that Ansible and Packer are installed and available. If they are not, they will be installed to `images/capi/.bin`. This directory will need to be added to your `$PATH`.

### Hypervisor

The image is built using KVM hypervisor.

### Prerequisites for all images

- [Packer](https://www.packer.io/intro/getting-started/install.html)
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.8.0

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

### Building QCOW2 Image

From the `images/capi` directory, run `make build-qemu-ubuntu-1804`. The image is built and located in `images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION`.
