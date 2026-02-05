# Azure SIG Image Builder - GitHub Actions Workflows

This directory contains GitHub Actions workflows for building and publishing Azure VHD images using the image-builder project. These workflows are the GitHub Actions equivalent of the Azure DevOps pipelines in `images/capi/packer/azure/.pipelines/`.

## Workflows Overview

| Workflow | File | Description |
|----------|------|-------------|
| Build Azure SIG Image | `build-azure-sig.yaml` | Main orchestrator workflow that coordinates all stages |
| Build (reusable) | `azure-sig-build.yaml` | Builds the Kubernetes node image and publishes to staging gallery |
| Test (reusable) | `azure-sig-test.yaml` | Tests the built image by creating a CAPI cluster |
| Promote (reusable) | `azure-sig-promote.yaml` | Promotes the image to the community gallery |
| Clean (reusable) | `azure-sig-clean.yaml` | Cleans up staging resources |

## Pipeline Stages

```
┌─────────┐    ┌──────────┐    ┌─────────────┐    ┌─────────┐
│  Build  │───▶│   Test   │───▶│   Promote   │───▶│  Clean  │
└─────────┘    └──────────┘    └─────────────┘    └─────────┘
                 (optional)     (requires approval)  (always)
```

1. **Build**: Builds the Kubernetes node image using Packer and publishes it to a staging Azure Compute Gallery
2. **Test**: (Optional) Creates a test CAPI cluster using the built image to validate it works correctly
3. **Promote**: (Requires approval) Promotes the image from staging to the community gallery for public access
4. **Clean**: Cleans up staging resources (managed image and staging gallery version)

## Usage

### Triggering the Workflow

1. Go to the **Actions** tab in the GitHub repository
2. Select **Build Azure SIG Image** from the workflows list
3. Click **Run workflow**
4. Fill in the required inputs:

| Input | Required | Description | Example |
|-------|----------|-------------|---------|
| `kubernetes_version` | Yes | Kubernetes version to build | `1.31.1` |
| `os` | Yes | Operating system | `Ubuntu`, `AzureLinux`, or `Windows` |
| `os_version` | Yes | OS version | `24.04`, `22.04`, `2022-containerd` |
| `resource_group` | No | Azure resource group | `cluster-api-gallery` |
| `staging_gallery_name` | No | Staging gallery name | `staging_gallery` |
| `gallery_name` | No | Community gallery name | `community_gallery` |
| `packer_flags` | No | Additional Packer flags | `--on-error=ask` |
| `tags` | No | Custom tags for the image | `env=prod team=infra` |
| `skip_test` | No | Skip the test stage | `true` (default) |
| `skip_promote` | No | Skip the promote stage | `false` |

### Supported OS and Version Combinations

| OS | Versions |
|----|----------|
| Ubuntu | `22.04`, `24.04` |
| AzureLinux | `3` |
| Windows | `2022-containerd`, `2025-containerd` |

## Setup Requirements

### 1. Azure OIDC Authentication

Configure Azure OIDC (OpenID Connect) authentication for passwordless authentication from GitHub Actions:

1. Create an Azure AD application and service principal
2. Configure federated credentials for the GitHub repository
3. Grant the service principal necessary permissions on your Azure subscription

Add the following secrets to your GitHub repository or organization:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Azure AD application (client) ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

For detailed instructions, see: [Azure Login with OIDC](https://github.com/azure/login#login-with-openid-connect-oidc-recommended)

### 2. GitHub Environment for Approvals

Create a GitHub Environment for the promotion approval gate:

1. Go to **Settings** → **Environments**
2. Create a new environment named `image-promotion-approval`
3. Enable **Required reviewers** and add the appropriate team members
4. Optionally configure deployment branches and wait timer

### 3. Repository/Organization Variables

Set the following variables in your repository or organization settings for the promotion stage:

| Variable | Description | Example |
|----------|-------------|---------|
| `EULA_LINK` | URL to the EULA for the image | `https://example.com/eula` |
| `PUBLISHER_EMAIL` | Email for the image publisher | `team@example.com` |
| `PUBLISHER_URI` | URI for the image publisher | `https://example.com` |
| `SIG_PUBLISHER` | Publisher name for image definitions | `MyOrganization` |

### 4. Azure Resources

Ensure the following Azure resources are set up:

- **Resource Group**: A resource group for the compute galleries (default: `cluster-api-gallery`)
- **Staging Gallery**: An Azure Compute Gallery for initial image publishing
- **Community Gallery**: An Azure Compute Gallery with community permissions for public access

The workflows will create these resources if they don't exist, provided the service principal has sufficient permissions.

### Required Azure RBAC Permissions

The service principal needs the following permissions:

- `Contributor` on the resource group (or subscription)
- `User Access Administrator` if creating new resource groups
- For community galleries: permissions to create and manage Shared Image Galleries

## Artifacts

The workflows produce the following artifacts:

| Artifact | Description | Retention |
|----------|-------------|-----------|
| `publishing-info` | JSON file with image metadata from the build stage | 7 days |
| `sig-publishing` | JSON file with community gallery publishing details | 30 days |

## Differences from Azure DevOps Pipelines

| Feature | Azure DevOps | GitHub Actions |
|---------|--------------|----------------|
| Authentication | Service Connection | Azure OIDC via `azure/login@v2` |
| Approvals | ADO Environments | GitHub Environments |
| Artifacts | Pipeline Artifacts | GitHub Actions Artifacts |
| Variables | Pipeline Variables | Workflow Inputs + Repository Variables |
| Templates | YAML Templates | Reusable Workflows (`workflow_call`) |

## Troubleshooting

### Common Issues

1. **Authentication failures**
   - Verify OIDC credentials are correctly configured
   - Check that the federated credential matches the repository and branch

2. **Permission denied errors**
   - Ensure the service principal has sufficient Azure RBAC permissions
   - Verify the subscription ID is correct

3. **Packer build failures**
   - Check the Packer output in the build logs
   - Verify the OS/version combination is supported
   - Ensure the Kubernetes version exists

4. **Test stage failures**
   - The test stage requires the Azure CAPI CLI extension
   - Ensure sufficient quota for VMs in the target region

### Debug Mode

To enable debug output, add `--on-error=ask` to the `packer_flags` input (note: this may cause the build to hang waiting for input in CI).

For more verbose logging, you can enable GitHub Actions debug logging by setting the `ACTIONS_STEP_DEBUG` secret to `true`.

## Related Documentation

- [Image Builder Documentation](../../docs/book/src/capi/capi.md)
- [Azure Provider Documentation](../../images/capi/packer/azure/README.md)
- [Azure DevOps Pipelines](../../images/capi/packer/azure/.pipelines/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Azure Login Action](https://github.com/azure/login)
