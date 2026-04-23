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

Since Outscale does not provide a Flatcar OMI, the Flatcar build uses an Ubuntu OMI as a
bootstrap environment. The build process installs Flatcar to disk using `flatcar-install`,
reboots into Flatcar, and then provisions it with Ansible.

The following additional environment variables are required for Flatcar builds:
```
FLATCAR_CHANNEL: Flatcar release channel (stable, beta, alpha). Defaults to stable.
FLATCAR_VERSION: Flatcar version. Defaults to current (latest).
```

Example:
```bash
FLATCAR_CHANNEL=stable FLATCAR_VERSION=current make build-osc-flatcar
```
