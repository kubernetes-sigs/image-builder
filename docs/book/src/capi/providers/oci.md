# Building Images for Oracle Cloud Infrastructure (OCI)

## Prerequisites

- An OCI account
- [The OCI plugin for Packer supports three options for authentication](https://www.packer.io/docs/builders/oracle/oci#authentication)
  . You may use any of these options when building the Cluster API images.

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building OCI images are managed by running:

```bash
make deps-oci
```

From the `images/capi` directory, run `make build-do-<OS>` where `<OS>` is
the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `oci`
directory includes several JSON files that define the default configuration for
the different operating systems.

| File | Description |
|------|-------------|
| `oracle-linux-8.json` | The settings for the Oracle Linux 8 image |
| `ubuntu-1804.json` | The settings for the Ubuntu 18.04 image |
| `ubuntu-2004.json` | The settings for the Ubuntu 20.04 image |

#### Common options

This table lists several common options that a user must set via
`PACKER_VAR_FILES` to customize their build behavior.  This is not an exhaustive
list, and greater explanation can be found in the
[Packer documentation for the OCI builder](https://www.packer.io/docs/builders/oracle/oci#required-configuration-parameters).

| Variable | Description | Default | Mandatory |
|----------|-------------|---------|---------|
| `compartment_ocid` | The OCID of the compartment that the instance will run in. |  | Yes |
| `subnet_ocid` |  The name of the subnet within which a new instance is launched and provisioned. |  | Yes |
| `availability_domain` | The name of the Availability Domain within which a new instance is launched and provisioned. The names of the Availability Domains have a prefix that is specific to your tenancy. |  | Yes |
| `shape` | An OCI region. Overrides value provided by the OCI config file if present. This cannot be used along with the use_instance_principals key. | `VM.Standard.E4.Flex` | No |

#### Steps to create Packer VAR file

Create a file with the following contents and name it as `oci.json`

```json
{
  "compartment_ocid": "Fill compartment OCID here",
  "subnet_ocid": "Fill Subnet OCID here",
  "availability_domain": "Fill Availbility Domain here"
}
```

#### Example make command with Packer VAR file

```bash
PACKER_VAR_FILES=oci.json make build-oci-oracle-linux-8
```