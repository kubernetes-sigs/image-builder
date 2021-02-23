# Provisioning Flatcar with Packer + Ansible

- [Provisioning Flatcar with Packer + Ansible](#provisioning-flatcar-with-packer--ansible)
  - [Overview](#overview)
  - [Usage](#usage)
  - [Notes](#notes)
  - [TODOs](#todos)

## Overview

This is a Cluster API image builder for [Flatcar Container Linux](https://kinvolk.io/flatcar-container-linux).

On the Packer side it includes `packer/qemu/flatcar.json` and `packer/qemu/packer.json`.
In `packer/config/` it also includes some other JSON files with configuration for
ansible and packages installed with Ansible.

On the Ansible side there's some preliminary playbook in `ansible/`.

## Prerequisites

* [packer](https://packer.io/) v1.5 or newer
* [ansible](https://github.com/ansible/ansible/releases) v2.10 or newer
* (optional) libvirtd, libvirt-client, vagrant, and virt-manager (for testing)

### Recommendation

Before running `packer build` command, please make sure the following:

* Your system should not be under heavy CPU load. It can prevent Packer's VNC commands from being passed in.
* During the VNC phase of Packer build, please do not open another VNC viewer to the same port. That could also prevent VNC commands from being passed in.

## Usage

Flatcar qemu images can be built using the Makefile; a convenience wrapper
script is provided to import the VM into vagrant and to initialise `kubeadm`.

### Convenience wrapper script

The wrapper script will call `make` (see below) to build an image,
import the image to vagrant, start a VM, and initialise `kubeadm`. After the
script concluded, users are all set up and can start interacting with kubernetes.

Start a new build with
```shell
./hack/image-build-flatcar.sh [<channel>] [<release-version>]
```

Flatcar Container Linux maintains four distinct
channels: `alpha`, `beta`, `stable`, and `edge`. For details please refer to
the [releases page](https://kinvolk.io/flatcar-container-linux/releases/).

The build script will default to the latest release of the `stable` channel.

After provisioning concluded the script will ask you to export flatcar channel
and release version environment variables:
```shell
  export FLATCAR_CHANNEL='<channel>'
  export FLATCAR_VERSION='<version>'
  export VAGRANT_VAGRANTFILE='<vagrantfile>'"
```

You're now set up to interact with your cluster via `vagrant ssh`. Try e.g.

```shell
$ vagrant ssh 'kubectl cluster-info'
Kubernetes master is running at https://10.0.2.15:6443
KubeDNS is running at https://10.0.2.15:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

Get an overview of all images built by using `hack/boxes-flatcar.sh`. The
helper script will list all available images / VMs and will output environment
variables for convenient copy/paste.

### Makefile build

Make target `build-qemu-flatcar` will build a Flatcar Container Linux qemu
image. The make variables `FLATCAR_CHANNEL` and `FLATCAR_VERSION` can be set to
build specific releases. THe build will default to the current stable release.

Example usage:
```shell
$ make build-qemu-flatcar
or
$ make FLATCAR_CHANNEL=beta build-qemu-flatcar
or
$ make FLATCAR_CHANNEL=stable FLATCAR_VERSION=2512.2.0 build-qemu-flatcar
or
$ make FLATCAR_CHANNEL=stable FLATCAR_VERSION=$(hack/image-grok-latest-flatcar-version.sh stable) \
  build-qemu-flatcar
```

## Notes

* `images/capi/ansible/roles/setup/tasks/bootstrap-flatcar.yml` installs python under `/opt`.
* `images/capi/ansible/roles/kubernetes/tasks/url.yml` installs artificts of Kubernetes and CNI under `/opt` and `/etc`, mainly because `/usr` is read-only in Flatcar.
* It unpacks only parts of containerd binaries, since Flatcar already has its own built-in containerd.
* To make containerd work correctly, we install Flatcar-specific config files for containerd, so it listens on its containerd socket `/run/docker/libcontainerd/docker-containerd.sock`.
* Since Flatcar has its own containerd socket, we need to also specify the socket name when running commands like `kubeadm config images pull`, `/opt/bin/ctr images import` as well as in `/etc/crictl.yaml`.
* We do not delete `/etc/kubeadm.yml` for Flatcar, because later steps running `kubeadm init` require the config to be in place.

## TODOs

* Make sure it works for other platforms than qemu & AWS
