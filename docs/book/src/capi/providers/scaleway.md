# Building Images for Scaleway

## Prerequisites for Scaleway

- A Scaleway account
- Export environment variable for `SCW_PROJECT_ID`, `SCW_ACCESS_KEY` and `SCW_SECRET_KEY`

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Scaleway images are managed by running:

```bash
make deps-scaleway
```

From the `images/capi` directory, run `make build-scaleway-<OS>` where `<OS>` is the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `scaleway`
directory includes the JSON files that define the default configuration for
the different operating systems.

| File                | Description                              |
| ------------------- | ---------------------------------------- |
| `rockylinux-9.json` | The settings for the Rocky Linux 9 image |
| `ubuntu-2204.json`  | The settings for the Ubuntu 22.04 image  |
| `ubuntu-2404.json`  | The settings for the Ubuntu 24.04 image  |
