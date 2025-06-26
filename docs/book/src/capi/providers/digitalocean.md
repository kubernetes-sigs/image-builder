# Building Images for DigitalOcean

## Prerequisites for DigitalOcean

- A DigitalOcean account
- The DigitalOcean CLI ([doctl](https://github.com/digitalocean/doctl#installing-doctl)) installed and configured
- Set an environment variable for your `DIGITALOCEAN_ACCESS_TOKEN`

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Digital Ocean images are managed by running:

```bash
make deps-do
```

From the `images/capi` directory, run `make build-do-<OS>` where `<OS>` is the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `digitalocean`
directory includes several JSON files that define the default configuration for
the different operating systems.

| File | Description |
|------|-------------|
| `ubuntu-2004.json` | The settings for the Ubuntu 20.04 image |
| `ubuntu-2204.json` | The settings for the Ubuntu 22.04 image |
| `ubuntu-2404.json` | The settings for the Ubuntu 24.04 image |
