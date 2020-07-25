# Building Images for Azure

## Prerequisites for Azure

- An Azure account
- The Azure CLI installed and configured
- Set environment variables for `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Azure images are managed by running:

```bash
make deps-azure
```

### Building Managed Images in Shared Image Galleries

From the `images/capi` directory, run `make build-azure-sig-ubuntu-1804`

### Building VHDs

From the `images/capi` directory, run `make build-azure-vhd-ubuntu-1804`
