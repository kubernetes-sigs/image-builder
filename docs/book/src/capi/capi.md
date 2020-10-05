# CAPI Images

The Image Builder can be used to build images intended for use with Kubernetes [CAPI](https://cluster-api.sigs.k8s.io/) providers. Each provider has its own format of images that it can work with. For example, AWS instances use AMIs, and vSphere uses OVAs.

## Prerequisites

[Packer](https://www.packer.io) and [Ansible](https://github.com/ansible/ansible) are used for building these images. This tooling has been forked and extended from the [Wardroom](https://github.com/heptiolabs/wardroom) project.

- [Packer](https://www.packer.io/intro/getting-started/install.html) version >= 1.6.0
- [Goss plugin for Packer](https://github.com/YaleUniversity/packer-provisioner-goss) version >= 1.2.0
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.10.0

If any needed binaries are not present, they can be installed to `images/capi/.bin` with the `make deps` command. This directory will need to be added to your `$PATH`.

## Providers

* [AWS](./providers/aws.md)  
* [Azure](./providers/azure.md)
* [DigitalOcean](./providers/digitalocean.md)
* Google *TODO*
* [OpenStack](./providers/openstack.md)
* [vSphere](./providers/vsphere.md)

## Make targets

Within this repo, there is a Makefile located at `images/capi/Makefile` that can be used to create the default images.

Run `make` or `make help` to see the current list of targets. The targets are categorized into `Dependencies`, `Builds`, and `Cleaning`. The Dependency targets will check that your system has the proper tools installed to run the build for your specific provider. If the dependencies are not present, they will be installed.

## Configuration

The `images/capi/packer/config` directory includes several JSON files that define the default configuration for the images:

| File | Description |
|------|-------------|
| `packer/config/ansible-args.json` | A common set of variables that are sent to the Ansible playbook |
| `packer/config/cni.json` | The version of Kubernetes CNI to install |
| `packer/config/containerd.json` | The version of containerd to install and customizations specific to the containerd runtime |
| `packer/config/kubernetes.json` | The version of Kubernetes to install |

### Customization

Several variables can be used to customize the image build.

| Variable | Description | Default |
|----------|-------------|---------|
| `custom_role` | If set to `"true"`, this will cause `image-builder` to run a custom Ansible role right before the `sysprep` role to allow for further customization. | `"false"` |
| `custom_role_names` | This must be set if `custom_role` is set to `"true"`, and is the space delimited string of the roles to run. If the role is placed in the `ansible/roles` directory, it can be referenced by name. Otherwise, it must be a fully qualified path to the role. | `""` |
| `disable_public_repos` | If set to `"true"`, this will disable all existing package repositories defined in the OS before doing any package installs. The `extra_repos` variable *must* be set for package installs to succeed. | `"false"` |
| `extra_debs` | This can be set to a space delimited string containing the names of additional deb packages to install | `""` |
| `extra_repos` | A space delimited string containing the names of files to add to the image containing repository definitions. The files should be given as absolute paths. | `""` |
| `extra_rpms` | This can be set to a space delimited string containing the names of additional RPM packages to install | `""` |
| `http_proxy` | This can be set to URL to use as an HTTP proxy during the Ansible stage of building | `""` |
| `https_proxy` | This can be set to URL to use as an HTTPS proxy during the Ansible stage of building | `""` |
| `no_proxy` | This can be set to a comma-delimited list of domains that should be exluded from proxying during the Ansible stage of building | `""` |
| `reenable_public_repos` | If set to `"false"`, the package repositories disabled by setting `disable_public_repos` will remain disabled at the end of the build. | `"true"` |
| `remove_extra_repos` | If set to `"true"`, the package repositories added to the OS through the use of `extra_repos` will be removed at the end of the build. | `"false"` |
| `containerd_pause_image` | This can be used to override the default containerd pause image used to hold the network namespace and IP for the pod. | `"k8s.gcr.io/pause:3.2"` |
| `containerd_additional_settings` | This is a string, base64 encoded, that contains additional configuration for containerd. It must be version 2 and not contain the pause image configuration block. See `image-builder/images/capi/ansible/roles/containerd/templates/etc/containerd/config.toml` for the template. | `null` |

The variables found in `packer/config/*.json` or `packer/<provider>/*.json` should not need to be modified directly. For customization it is better to create a JSON file with your changes and provide it via the `PACKER_VAR_FILES` environment variable. Variables set in this file will override any previous values. Multiple files can be passed via `PACKER_VAR_FILES`, with the last file taking precedence over any others.

#### Examples

##### Passing a single extra var file

```sh
PACKER_VAR_FILES=var_file_1.json make ...
```

##### Passing multiple extra var files

```sh
PACKER_VAR_FILES="var_file_1.json var_file_2.json" make ...
```

##### Passing in extra packages to the image

If you wanted to install the RPMs `nfs-utils` and `net-tools`, create a file called `extra_vars.json` and populate with the following:

```json
{
  "extra_rpms": "\"nfs-utils net-tools\""
}
```

Note that since the `extra_rpms` variable is a string, and we need the string to be quoted to preserve the space when placed on the command line, having the escaped double-quotes is required.

Then, execute the build (using a Photon OVA as an example) with the following:

```sh
PACKER_VAR_FILES=extra_vars.json make build-node-ova-local-photon-3
```

##### Disabling default repos and using an internal package mirror

A common use-case within enterprise environments is to have a package repository available on an internal network to install from rather than reaching out to the internet. To support this, you can inject custom repository definitions into the image, and optionally disable the use of the default ones.

For example, to build an image using only an internal mirror, create a file called `internal_repos.json` and populate it with the following:


```json
{
  "disable_public_repos": "true",
  "extra_repos": "/home/<user>/mirror.repo",
  "remove_extra_repos": "true"
}
```

This example assumes that you have an RPM repository definition available at `/home/<user>/mirror.repo`, and it is correctly configured to point to your internal mirror. It will be added to the image within `/etc/yum.repos.d`, with all existing repositories found with `/etc/yum.repos.d` disabled by setting `disable_public_repos` to `"true"`. Furthermore, the (optional) use of `"remove_extra_repos"` means that at the end of the build, the repository definition that was added will be removed. This is useful if the image you are building will be shared externally and you do not wish to include a file with internal network services and addresses.

For Ubuntu images, the process works the same but you would need to add a `.list` file pointing to your DEB package mirror.

Then, execute the build (using a Photon OVA as an example) with the following:

```sh
PACKER_VAR_FILES=internal_repos.json make build-node-ova-local-photon-3
```

##### Setting up an HTTP Proxy

The Packer tool itself honors the standard env vars of `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY`. If these variables are set and exported, they will be honored if Packer needs to download an ISO during a build. However, in order to use these proxies with Ansible (for use during package installation or binary download), we need to pass them via JSON file.

For example, to set the HTTP_PROXY env var for the Ansible stage of the build, create a `proxy.json` and populate it with the following:

```json
{
  "http_proxy": "http://proxy.corp.com"
}
```

Then, execute the build (using a Photon OVA as an example) with the following:

```sh
PACKER_VAR_FILES=proxy.json make build-node-ova-local-photon-3
```
