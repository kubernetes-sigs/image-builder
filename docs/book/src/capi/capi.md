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

The `images/capi/packer/config` directory includes several JSON files that define the default configuration for the images:

| File | Description |
|------|-------------|
| `packer/config/ansible-args.json` | A common set of variables that are sent to the Ansible playbook |
| `packer/config/cni.json` | The version of Kubernetes CNI to install |
| `packer/config/containerd.json` | The version of containerd to install |
| `packer/config/kubernetes.json` | The version of Kubernetes to install |

### Customization

Several variables can be used to customize the image build.

| Variable | Description | Default |
|----------|-------------|---------|
| `extra_debs` | This can be set to a space delimited string containing the names of additional deb packages to install | `""` |
| `extra_rpms` | This can be set to a space delimited string containing the names of additional RPM packages to install | `""` |

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
PACKER_VAR_FILES=extra_vars.json make build-ova-photon-3
```


## Kubernetes versions
| Tested Kubernetes Versions |
|---------|
| `1.14.x` |
| `1.15.x` |
| `1.16.x` |
| `1.17.x` |
