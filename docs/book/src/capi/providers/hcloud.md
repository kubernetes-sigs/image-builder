# Building Images for Hetzner Hcloud

## Prerequisites for Hetzner Hcloud

- A Hetzner account
- Set the environment variables `HCLOUD_LOCATION` and `HCLOUD_TOKEN` for your hcloud project

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building hcloud images are managed by running:

```bash
make deps-hcloud
```

From the `images/capi` directory, run `make build-hcloud-<OS>` where `<OS>` is the desired operating system. The available choices are listed via `make help`. For example: Use `make build-hcloud-ubuntu-2404` to build an Ubuntu 22.04 snapshot in hcloud.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `hcloud`
directory includes several JSON files that define the default configuration for
the different operating systems.

| File                 | Description                              |
|----------------------|------------------------------------------|
| `flatcar.json`       | The settings for the Flatcar image       |
| `flatcar-arm64.json` | The settings for the Flatcar arm64 image |
| `rockylinux-8.json`  | The settings for the RockyLinux 8 image  |
| `rockylinux-9.json`  | The settings for the RockyLinux 9 image  |
| `ubuntu-2204.json`   | The settings for the Ubuntu 22.04 image  |
| `ubuntu-2404.json`   | The settings for the Ubuntu 24.04 image  |
