# Building Images for Vsphere

## Prerequisites

The `make deps-vsphere` target will test that Ansible and Packer are installed and available. If they are not, they will be installed to `images/capi/.bin`. This directory will need to be added to your `$PATH`.

### Prerequisites for all images

- [Packer](https://www.packer.io/intro/getting-started/install.html) version >= 1.5.4
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.8.0

### Prerequisites for Vsphere-api

- Access to an vSphere 6.5+
- Create a configuration file with the following format (`cluster` can be replace by `host`):
```
{
    "kubernetes_semver":"v1.17.3",
    "vcenter_server":"FQDN of vcenter",
    "username":"vcenter_username",
    "password":"vcenter_password",
    "datastore":"template_datastore",
    "folder": "template_folder_on_vcenter",
    "cluster": "esxi_cluster_used_for_template_creation",
    "network": "network_attached_to_template"
}
```

## Building Images

Set the  the path to the configuration file in the environment variable `PACKER_VAR_FILE` and from the `images/capi` directory, run `make build-vsphere-<OS>`, where `<OS>` is the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `vsphere` directory includes several JSON files that define the configuration for the images:

| File | Description |
|------|-------------|
| `vsphere-centos-7.json` | The settings for the CentOS 7 image |
| `vsphere-photon-3.json` | The settings for the Photon 3 image |
| `vsphere-ubuntu-1804.json` | The settings for the Ubuntu 1804 image |
| `vsphere-ubuntu-2004.json` | The settings for the Ubuntu 2004 image |

The templates are built and located in the vSphere folder indicated in the configuration file and will be named `<OS>-kube-v<kubernetes_version>``
