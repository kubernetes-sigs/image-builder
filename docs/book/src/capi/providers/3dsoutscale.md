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
| `ubuntu-2204.json` | The settings for the Ubuntu 22.04 image |
| `ubuntu-2404.json` | The settings for the Ubuntu 24.04 image |
| `ubuntu-2604.json` | The settings for the Ubuntu 26.04 image |
| `flatcar.json` | The settings for the Flatcar image |

You must have your [Access Keys](https://docs.outscale.com/en/userguide/About-Access-Keys.html).
You must have your [Account Id](https://docs.outscale.com/en/userguide/Getting-Information-About-Your-Account-and-Quotas.html).
Please set the following environment variables before building image:
```
OSC_SECRET_KEY: Outscale Secret Key
OSC_REGION: Outscale Region
OSC_ACCESS_KEY: Outscale Access Key Id
OSC_ACCOUNT_ID: Outscale Account Id
```

### Flatcar

Flatcar has no public OMI on Outscale. Import the official Flatcar Outscale
image into your account first, in each region you build in, following the
[Flatcar documentation](https://www.flatcar.org/docs/latest/deploy/cloud/outscale/).

The build looks up an OMI owned by your account and named
`flatcar-${FLATCAR_CHANNEL}-${FLATCAR_VERSION}`, the name used in that
documentation. `FLATCAR_VERSION=current` resolves to the latest release of
the channel, so pin the version you imported:

```bash
FLATCAR_CHANNEL=alpha FLATCAR_VERSION=4890.0.0 make build-osc-flatcar
```

To use another name or owner, override `image_name` and `owner` in a file
passed with `PACKER_VAR_FILES`.
