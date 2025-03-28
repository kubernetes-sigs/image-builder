# Including ECR Credential Provider

Starting with Kuberentes v1.27 the cloud credential providers are no longer included in-tree and need to be included as external binaries and referenced by the Kubelet.

To do this with image-builder you enable the use of [ecr-credential-provider](https://github.com/kubernetes/cloud-provider-aws/#aws-credential-provider) by setting the `ecr_credential_provider` packer variable to `true`.

Once enabled, the `ecr-credential-provider` binary will be downloaded, a `CredentialProviderConfig` config will be created, and the kubelet flags will be updated to reference both of these.

In most setups, this should be all that is needed but the following vars can be set to override various properties:

| variable | default | description |
| --- | --- | --- |
| ecr_credential_provider_version | "v1.31.0" | The release version of [cloud-provider-aws](https://github.com/kubernetes/cloud-provider-aws/) to use  |
| ecr_credential_provider_os | "linux" | The operating system |
| ecr_credential_provider_arch | "amd64" | The architecture |
| ecr_credential_provider_base_url | "https://storage.googleapis.com/k8s-artifacts-prod/binaries/cloud-provider-aws" | The base URL of where to get the binary from |
| ecr_credential_provider_install_dir | "/opt/bin" | The location to install the binary into |
| ecr_credential_provider_binary_filename | "ecr-credential-provider" | The filename to use for the downloaded binary |
| ecr_credential_provider_match_images | ["*.dkr.ecr.*.amazonaws.com", "*.dkr.ecr.*.amazonaws.com.cn"] | An array of globs to use for matching images that should use the credential provider. (If using gov-cloud you may need to change this) |
| ecr_credential_provider_aws_profile | "default" | The AWS profile to use with the credential provider |

