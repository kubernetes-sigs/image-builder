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
* [CloudStack](./providers/cloudstack.md)
* [DigitalOcean](./providers/digitalocean.md)
* [GCP](./providers/gcp.md)
* [HuaweiCloud](./providers/huaweicloud.md)
* [IBM Cloud](./providers/ibmcloud.md)
* [Nutanix](./providers/nutanix.md)
* [OCI](./providers/oci.md)
* [3DSOutscale](./providers/3dsoutscale.md)
* [OpenStack](./providers/openstack.md)
* [OpenStack remote image building](./providers/openstack-remote.md)
* [Raw](./providers/raw.md)
* [VirtualBox](./providers/virtualbox.md)
* [vSphere](./providers/vsphere.md)
* [Proxmox](./providers/proxmox.md)

## Make targets

Within this repo, there is a Makefile located at `images/capi/Makefile` that can be used to create the default images.

Run `make` or `make help` to see the current list of targets. The targets are categorized into `Dependencies`, `Builds`, and `Cleaning`. The Dependency targets will check that your system has the proper tools installed to run the build for your specific provider. If the dependencies are not present, they will be installed.

## Configuration

The `images/capi/packer/config` directory includes several JSON files that define the default configuration for the images:

| File                              | Description                                                                                                                                           |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packer/config/ansible-args.json` | A common set of variables that are sent to the Ansible playbook                                                                                       |
| `packer/config/cni.json`          | The version of Kubernetes CNI to install                                                                                                              |
| `packer/config/containerd.json`   | The version of containerd to install and customizations specific to the containerd runtime                                                            |
| `packer/config/kubernetes.json`   | The version of Kubernetes to install. The default version is kept at n-2. See [Customization](#customization) section below for overriding this value |

Due to OS differences, Windows images has additional configuration in the `packer/config/windows` folder.  See [Windows documentation](./windows/windows.md) for more details.

### Customization

Several variables can be used to customize the image build.

| Variable                                                                                                                   | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Default                       |
| -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------- |
| `firstboot_custom_roles_pre`<br />`firstboot_custom_roles_post`<br />`node_custom_roles_pre`<br />`node_custom_roles_post` | Each of these four variables allows for giving a space delimited string of custom Ansible roles to run at different times. The "pre" roles run as the very first thing in the playbook (useful for setting up environment specifics like networking changes), and the "post" roles as the very last (useful for undoing those changes, custom additions, etc). Note that the "post" role does run before the "sysprep" role in the "node" playbook, as the "sysprep" role seals the image. If the role is placed in the `ansible/roles` directory, it can be referenced by name. Otherwise, it must be a fully qualified path to the role. | `""`                          |
| `disable_public_repos`                                                                                                     | If set to `"true"`, this will disable all existing package repositories defined in the OS before doing any package installs. The `extra_repos` variable *must* be set for package installs to succeed.                                                                                                                                                                                                                                                                                                                                                                                                                                     | `"false"`                     |
| `extra_debs`                                                                                                               | This can be set to a space delimited string containing the names of additional deb packages to install                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `""`                          |
| `extra_repos`                                                                                                              | A space delimited string containing the names of files to add to the image containing repository definitions. The files should be given as absolute paths.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `""`                          |
| `extra_rpms`                                                                                                               | This can be set to a space delimited string containing the names of additional RPM packages to install                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `""`                          |
| `http_proxy`                                                                                                               | This can be set to URL to use as an HTTP proxy during the Ansible stage of building                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | `""`                          |
| `https_proxy`                                                                                                              | This can be set to URL to use as an HTTPS proxy during the Ansible stage of building                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `""`                          |
| `kubernetes_deb_version`                                                                                                   | This can be set to the version of Kubernetes which will be installed in debian based image                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `"1.26.7-1.1"`                |
| `kubernetes_rpm_version`                                                                                                   | This can be set to the version of Kubernetes which will be installed in rpm based image                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | `"1.26.7"`                    |
| `kubernetes_semver`                                                                                                        | This can be set to semantic verion of Kubernetes which will be installed in the image                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | `"v1.26.7"`                   |
| `kubernetes_series`                                                                                                        | This can be set to series version Kubernetes which will be installed in the image                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | `"v1.26"`                     |
| `netplan_removal_excludes`                                                                                                 | This can be set to a space-delimited list of netplan files basename to keep from the image.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `""`                          |
| `no_proxy`                                                                                                                 | This can be set to a comma-delimited list of domains that should be excluded from proxying during the Ansible stage of building                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `""`                          |
| `reenable_public_repos`                                                                                                    | If set to `"false"`, the package repositories disabled by setting `disable_public_repos` will remain disabled at the end of the build.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `"true"`                      |
| `remove_extra_repos`                                                                                                       | If set to `"true"`, the package repositories added to the OS through the use of `extra_repos` will be removed at the end of the build.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `"false"`                     |
| `pause_image`                                                                                                              | This can be used to override the default pause image used to hold the network namespace and IP for the pod.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | `"registry.k8s.io/pause:3.9"` |
| `pip_conf_file`                                                                                                            | The path to a file to be copied into the image at `/etc/pip.conf` for use as a global config file. This file will be removed at the end of the build if `remove_extra_repos` is `true`.                                                                                                                                                                                                                                                                                                                                                                                                                                                    | `""`                          |
| `containerd_additional_settings`                                                                                           | This is a string, base64 encoded, that contains additional configuration for containerd. It must be version 2 and not contain the pause image configuration block. See `image-builder/images/capi/ansible/roles/containerd/templates/etc/containerd/config.toml` for the template.                                                                                                                                                                                                                                                                                                                                                         | `null`                        |
| `load_additional_components`                                                                                               | If set to `"true"`, the `load_additional_components` role will be executed. This needs to be set to `"true"` if any of `additional_url_images`, `additional_registry_images` or `additional_executables` are set to `"true"`                                                                                                                                                                                                                                                                                                                                                                                                               | `"false"`                     |
| `additional_url_images`                                                                                                    | Set this to `"true"` to load additional container images using a tar url. `additional_url_images_list` var should be set to a comma separated string of tar urls of the container images.                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `"false"`                     |
| `additional_registry_images`                                                                                               | Set this to `"true"` to load additional container images using their registry url. `additional_registry_images_list` var should be set to a comma separated string of registry urls of the container images.                                                                                                                                                                                                                                                                                                                                                                                                                               | `"false"`                     |
| `additional_executables`                                                                                                   | Set this to `"true"` to load additional executables from a url. `additional_executables_list` var should be set to a comma separated string of urls. `additional_executables_destination_path` should be set to the destination path of the executables.                                                                                                                                                                                                                                                                                                                                                                                   | `"false"`                     |
| `ansible_user_vars`                                                                                                        | A space delimited string that the user can pass to use in the ansible roles                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | `""`                          |
| `containerd_config_file`                                                                                                   | Custom containerd config file a user can pass to override the default. Use `ansible_user_vars` to pass this var                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `""`                          |
| `enable_containerd_audit`                                                                                                  | If set to `"true"`, auditd will be configured with containerd specific audit controls.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `"false"`                     |
| `kubernetes_enable_automatic_resource_sizing`                                                                              | If set to `"true"`, the kubelet will be configured to automatically size system-reserved for CPU and memory.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `"false"`                     |

The variables found in `packer/config/*.json` or `packer/<provider>/*.json` should not need to be modified directly. For customization it is better to create a JSON file with your changes and provide it via the `PACKER_VAR_FILES` environment variable. Variables set in this file will override any previous values. Multiple files can be passed via `PACKER_VAR_FILES`, with the last file taking precedence over any others.

#### Examples

##### Passing custom Kubernetes version

```sh
PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make ...
```

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

##### Configuring Containerd at runtime

Containerd default configuration has the following `imports` value:

```
imports = ["/etc/containerd/conf.d/*.toml"]
```

This allows you to place files at runtime in `/etc/containerd/conf.d/` that will then be merged with the rest of containerd configuration.

For example to enable containerd metrics, create a file `/etc/containerd/conf.d/metrics.toml` with the following:

```
[metrics]
  address = "0.0.0.0:1338"
  grpc_histogram = false
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


##### Loading additional components using `additional_components.json`

```json
{
  "additional_executables": "true",
  "additional_executables_destination_path": "/path/to/dest",
  "additional_executables_list": "http://path/to/exec1,http://path/to/exec2",
  "additional_s3": "true",
  "additional_s3_endpoint": "https://path-to-s3-endpoint",
  "additional_s3_access": "S3_ACCESS_KEY",
  "additional_s3_secret": "S3_SECRET_KEY",
  "additional_s3_bucket": "some-bucket",
  "additional_s3_object": "path/to/object",
  "additional_s3_destination_path": "/path/to/dest",
  "additional_s3_ceph": "true",
  "additional_registry_images": "true",
  "additional_registry_images_list": "plndr/kube-vip:0.3.4,plndr/kube-vip:0.3.3",
  "additional_url_images": "true",
  "additional_url_images_list": "http://path/to/image1.tar,http://path/to/image2.tar",
  "load_additional_components": "true"
}
```

##### Using `ansible_user_vars` to pass custom variables

```json
{
  "ansible_user_vars": "var1=value1 var2={{ user `myvar2`}}",
  "myvar2": "value2"
}
```

##### Enabling Ansible custom roles

Put the Ansible role files in the `ansible/roles` directory.

```json
{
  "firstboot_custom_roles_pre": "setupRole",
  "node_custom_roles_post": "role1 role2"
}
```

Note, for backwards compatibility reasons, the variable `custom_role_names` is still accepted as an alternative to `node_custom_roles_post`, and they are functionally equivalent.
