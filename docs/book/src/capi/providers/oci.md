# Building Images for Oracle Cloud Infrastructure (OCI)

## Prerequisites

- An OCI account
- [The OCI plugin for Packer supports three options for authentication](https://www.packer.io/docs/builders/oracle/oci#authentication)
  . You may use any of these options when building the Cluster API images.

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building OCI images are managed by running the following command from images/capi directory.

```bash
make deps-oci
```

From the `images/capi` directory, run `make build-oci-<OS>` where `<OS>` is
the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `oci`
directory includes several JSON files that define the default configuration for
the different operating systems.

| File | Description |
|------|-------------|
| `oracle-linux-8.json` | The settings for the Oracle Linux 8 image |
| `oracle-linux-9.json` | The settings for the Oracle Linux 9 image |
| `ubuntu-2204.json` | The settings for the Ubuntu 22.04 image |
| `windows-2019.json` | The settings for the Windows Server 2019 image |
| `windows-2022.json` | The settings for the Windows Server 2022 image |

#### Common options

This table lists several common options that a user must set via
`PACKER_VAR_FILES` to customize their build behavior.  This is not an exhaustive
list, and greater explanation can be found in the
[Packer documentation for the OCI builder](https://www.packer.io/docs/builders/oracle/oci#required-configuration-parameters).

| Variable | Description | Default | Mandatory |
|----------|-------------|---------|---------|
| `base_image_ocid` | The OCID of an existing image to build upon. | | No |
| `compartment_ocid` | The OCID of the compartment that the instance will run in. |  | Yes |
| `subnet_ocid` |  The OCID of the subnet within which a new instance is launched and provisioned. |  | Yes |
| `availability_domain` | The name of the Availability Domain within which a new instance is launched and provisioned. The names of the Availability Domains have a prefix that is specific to your tenancy. |  | Yes |
| `shape` | An OCI region. Overrides value provided by the OCI config file if present. This cannot be used along with the use_instance_principals key. | `VM.Standard.E4.Flex` | No |

#### Steps to create Packer VAR file

Create a file with the following contents and name it as `oci.json`

```json
{
  "compartment_ocid": "Fill compartment OCID here",
  "subnet_ocid": "Fill Subnet OCID here",
  "availability_domain": "Fill Availability Domain here"
}
```

#### Example make command with Packer VAR file

```bash
PACKER_VAR_FILES=oci.json make build-oci-oracle-linux-8
```

#### Build an Arm based image

Building an Arm based image requires some overrides to use the correct installation files . An example for an
`oci.json` file  for Arm is shown below. The parameters for containerd, crictl and Kubernetes
has to point to the corresponding URL for Arm. The containerd SHA can be changed appropriately, the containerd version
is defined in images/capi/packer/config/containerd.json.

```json
{
  "compartment_ocid": "Fill compartment OCID here",
  "subnet_ocid": "Fill Subnet OCID here",
  "availability_domain": "Fill Availability Domain here",
  "shape": "VM.Standard.A1.Flex",
  "containerd_url": "https://github.com/containerd/containerd/releases/download/v{{user `containerd_version`}}/containerd-{{user `containerd_version`}}-linux-arm64.tar.gz",
  "crictl_url": "https://github.com/kubernetes-sigs/cri-tools/releases/download/v{{user `crictl_version`}}/crictl-v{{user `crictl_version`}}-linux-arm64.tar.gz",
  "kubernetes_rpm_repo": "https://packages.cloud.google.com/yum/repos/kubernetes-el7-aarch64",
  "containerd_sha256": "9ac616b5f23c1d10353bd45b26cb736efa75dfef31a2113baff2435dbc7becb8",
  "runc_sha256": "4ef19ab21ce1ae5a01e1d3fa5b005e45cdf59f5d3ab32541c9e262cb2b2d3451",
  "runc_url": "https://github.com/opencontainers/runc/releases/download/v{{user `runc_version`}}/runc.arm64",
}
```

### Building a Windows image

> NOTE: In order to use Windows with CAPI a Baremetal instance is required. This means a Baremetal instance is required for
> building the image as well. The OCIDs for the 2019 Datacenter edition of Windows can be found in their documentation:
>
> - [Windows server 2019](https://docs.oracle.com/iaas/images/image/ffa1ec8d-694e-4df7-b5ec-3e8061a7ecdf/)

> NOTE: It is important to make sure the shape used at image build time is used when launching an instance.
>
> Example: If `BM.Standard2.52` is used to build, then only `BM.Standard2.52` can be used for the newly
> created image.

#### Windows environment variables

| Variable | Description | Default | Mandatory |
|----------|-------------|---------|---------|
| `OPC_USER_PASSWORD` | The password to set the OPC user to when creating the image. This will be used for accessing instances using this image. |  | Yes |

> NOTE: Your new password must be at least 12 characters long and must comply with
[Microsoft's password policy](https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2012-R2-and-2012/hh994562(v=ws.11)).
If the password doesn't comply WinRM will fail to connect to the instance since the
password failed to be updated.

> NOTE: The `OPC_USER_PASSWORD` will be set in the `winrm_bootstrap.txt` file temporarily, while building the image.
  This is required in order for WinRM to access the instance building the image. Once the build process is complete
  the password will be deleted along with the fil so the password isn't stored long term in a cleartext file.

#### Build a Windows based image

The following example JSON would use the [Windows Server 2019 Datacenter Edition BM E4 image in the us-ashburn-1 region](https://docs.oracle.com/iaas/images/image/ffa1ec8d-694e-4df7-b5ec-3e8061a7ecdf/).

```json
{
  "build_name": "windows",
  "base_image_ocid": "<image_OCID>",
  "ocpus": "128",
  "shape": "BM.Standard.E4.128",
  "region": "us-ashburn-1",
  "compartment_ocid": "Fill compartment OCID here",
  "subnet_ocid": "Fill Subnet OCID here",
  "availability_domain": "Fill Availability Domain here"
}
```
