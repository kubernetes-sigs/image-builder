# Building Images for 3DS OUTSCALE

## Prerequisites for 3DS OUTSCALE

- A Outscale account
- The Outscale CLI ([osc-cli](https://github.com/outscale/osc-cli)) installed and configured
- Set environment variables for `OSC_ACCESS_TOKEN`, for `OSC_SECRET_TOKEN` and for `OSC_REGION`


## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Outscale images are managed by running:

```bash
make deps-osc
```

From the `images/capi` directory, run `make build-osc-<OS>` where `<OS>` is the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `outscale`
directory includes several JSON files that define the default configuration for
the different operating systems.

| File | Description |
|------|-------------|
| `ubuntu-2004.json` | The settings for the Ubuntu 20.04 image |
