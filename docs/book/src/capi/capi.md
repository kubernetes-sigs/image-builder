# CAPI Images

The Image Builder can be used to build images intended for use with CAPI providers. Each provider has its own format of images that it can work with. For example, AWS instances use AMIs, and vSphere uses OVAs.

## Providers

* [AWS](./providers/aws.md)  
* [Azure](./providers/azure.md)
* Google *TODO*
* [vSphere](./providers/vsphere.md)

## Make targets

Within this repo, there is a Makefile located at `images/capi/Makefile` that can be used to create the default images.

Check the Makefile to see a list of images that may be built:

| Targets |
|---------|
| `make build-ami-default` |
| `make build-azure-sig-ubuntu-1804` |
| `make build-azure-vhd-ubuntu-1804` |
| `make build-esx-ova-centos-7` |
| `make build-esx-ova-ubuntu-1804` |
| `make build-gce-default` |
| `make build-ova-centos-7` |
| `make build-ova-photon-3` |
| `make build-ova-ubuntu-1804` |

## Configuration

The `images/capi/packer/config` directory includes several JSON files that define the configuration for the images:

| File | Description |
|------|-------------|
| `packer/config/kubernetes.json` | The version of Kubernetes to install |
| `packer/config/cni.json` | The version of Kubernetes CNI to install |
| `packer/config/containerd.json` | The version of containerd to install |

## Kubernetes versions
| Tested Kubernetes Versions |
|---------|
| `1.14.x` |
| `1.15.x` |
| `1.16.x` |
