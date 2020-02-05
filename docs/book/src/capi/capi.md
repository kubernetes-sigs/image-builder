# CAPI Images

The Image Builder can be used to build images intended for use with CAPI providers. Each provider has its own format of images that it can work with. For example, AWS instances use AMIs, and vSphere uses OVAs.

## Providers

* [AWS](./providers/aws.md)  
* [Azure](./providers/azure.md)
* [DigitalOcean](./providers/digitalocean.md)
* Google *TODO*
* [vSphere](./providers/vsphere.md)

## Make targets

Within this repo, there is a Makefile located at `images/capi/Makefile` that can be used to create the default images.

Run `make` or `make help` to see the current list of targets. The targets are categorized into `Dependencies`, `Builds`, and `Cleaning`. The Dependency targets will check that your system has the proper tools installed to run the build for your specific provider. If the dependencies are not present, they will be installed.

## Configuration

The `images/capi/packer/config` directory includes several JSON files that define the configuration for the images:

| File | Description |
|------|-------------|
| `packer/config/ansible-args.json` | A common set of variables that are sent to the Ansible playbook |
| `packer/config/cni.json` | The version of Kubernetes CNI to install |
| `packer/config/containerd.json` | The version of containerd to install |
| `packer/config/kubernetes.json` | The version of Kubernetes to install |

## Kubernetes versions
| Tested Kubernetes Versions |
|---------|
| `1.14.x` |
| `1.15.x` |
| `1.16.x` |
| `1.17.x` |
