# Building Images for Vultr

## Prerequisites for Vultr

- A Vultr account
- Export environment variable for `VULTR_API_KEY`

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building Vultr images are managed by running:

```bash
make deps-vultr
```

From the `images/capi` directory, run `make build-vultr-<OS>` where `<OS>` is the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `Vultr`
directory includes the JSON files that define the default configuration 
for the different operating systems.

| File | Description |
|------|-------------|
| `ubuntu-2204.json` | The settings for the Ubuntu 22.04 image |
| `ubuntu-2404.json` | The settings for the Ubuntu 24.04 image |
