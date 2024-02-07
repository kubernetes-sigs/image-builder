# GPU driver installation

The GPU drivers have to be installed via the `node_custom_roles_pre` option to avoid an issue where, should a
dist-upgrade install a new kernel,
the driver won't work when the image is booted. This is because the DKMS hook doesn't run when the driver
is installed after the kernel has been installed. To get around this, we install the drivers first.

# NVIDIA vGPU

To install the NVIDIA vGPU driver as part of the image build process, you must have a `.run` file and `.tok` file from
NVIDIA ready and available from an S3 endpoint.
Once done you need to reference those files in your packer file.

_This is because NVIDIA place the vGPU drivers behind a licensing wall which means you can't just use the standard
installation process for them._
_NVIDIA, as of July 2023, no longer support an internal licensing server being hosted by a customer._
_This role currently doesn't support installing the publicly available drivers._

An example of the fields you need are defined below. Make sure to review and change any fields where required.
If the gridd configuration or licensing .tok file are not required then you can omit the `gridd_feature_type`
and `nvidia_tok_location` respectively.

```json
{
  "ansible_user_vars": "gpu_vendor=nvidia nvidia_s3_url=https://s3-endpoint nvidia_bucket=nvidia nvidia_bucket_access=ACCESS_KEY nvidia_bucket_secret=SECRET_KEY nvidia_installer_location=NVIDIA-Linux-x86_64-525.85.05-grid.run nvidia_tok_location=client_configuration_token.tok gridd_feature_type=4",
  "node_custom_roles_pre": "gpu"
}

```

The `nvidia` custom role does not make use of the `load_additional_components->s3` role due to a conflict that can occur
when attempting to also use other aspects of `load_additional_components`.
As the `nvidia` role is loaded as part of `node_custom_roles_pre`, it means that `load_additional_components` could be
called out of order.

As a result they now require a `.tok` file to be available for licensing via their cloud services.
This file contains sensitive information and is unique to the company/license to which it is provided.

# AMD

Installing the AMD GPU driver is much more straightforward due to the public availability of the drivers.

An example of the fields you need are defined below. Make sure to review and change any fields where required.

```json
{
  "ansible_user_vars": "gpu_vendor=amd amd_version=6.0.2 amd_deb_version=6.0.60002-1 amd_usecase=dkms",
  "node_custom_roles_pre": "gpu"
}

```

_**It is highly recommended you read through
the [AMDGPU_Installer use-cases](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/amdgpu-install.html#use-cases)
first to ensure you supply the correct one.**_

_**For example, using the `rocm` use case will install +24GB of libraries as
well as the driver so your disk size will need to compensate for this.**_