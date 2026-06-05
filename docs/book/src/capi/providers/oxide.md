# Building Images for Oxide

## Prerequisites for Oxide

- Credentials for an Oxide rack, configured via either `OXIDE_PROFILE` or `OXIDE_HOST`/`OXIDE_TOKEN` in the environment.
- The following environment variables set:

  | Variable | Description |
  |----------|-------------|
  | `OXIDE_PROJECT` | Name or ID of the Oxide project to build the image in. |
  | `OXIDE_BOOT_DISK_IMAGE_ID` | UUID of the image to use as the build source. |

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Oxide images are managed by running:

```bash
make deps-oxide
```

From the `images/capi` directory, run `make build-oxide-<OS>` where `<OS>` is the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `oxide` directory includes per-OS JSON files that define defaults for each supported image:

| File | Description |
|------|-------------|
| `ubuntu-2404.json` | Settings for the Ubuntu 24.04 image |
