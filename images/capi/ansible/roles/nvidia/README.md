# NVIDIA GPU driver installation

To install the NVIDIA GPU driver as part of the image build process, you must have a `.run` file and `.tok` file from NVIDIA ready and available from an S3 endpoint.

Then all you need to do is reference those files in your packer file.

An example of the fields you need are defined below. Make sure to review and change any fields where required.

```json
{
  "ansible_user_vars": "additional_s3=true nvidia_s3_url=https://s3-endpoint nvidia_bucket=nvidia nvidia_bucket_access=ACCESS_KEY nvidia_bucket_secret=SECRET_KEY nvidia_installer_location=NVIDIA-Linux-x86_64-525.85.05-grid.run nvidia_tok_location=client_configuration_token.tok gridd_feature_type=4"
  "node_custom_roles_pre": "nvidia"
}

```

The role has to be installed via the `node_custom_roles_pre` option to avoid a known issue where should a dist-upgrade install a new kernel, 
the driver won't work with it when the image is booted. This is because the DKMS hook doesn't get run due to the driver 
being installed after the kernel has been installed. To get around this, we install the driver first.

The `nvidia` custom role makes use of the `s3->load_additional_components` role so that it can fetch the items required from an S3 endpoint.

The reasoning behind requiring an S3 endpoint was due to the fact NVIDIA will soon (July 2023) no longer support an internal licensing server being hosted by a customer.

As a result they now require a `.tok` file to be available for licensing via their cloud services.
This file contains sensitive information and is unique to the company/license to which it is provided.
