# Building Images for HuaweiCloud

## Prerequisites for HuaweiCloud ECS

- An HuaweiCloud account access method. That means `access_key` and `secret_key` are required.

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building HuaweiCloud images are managed by running:

```bash
make deps-huaweicloud
```

From the `images/capi` directory, run `make build-huaweicloud-<OS>`, where `<OS>` is
the desired operating system. The available choices are listed via `make help`.

To build all available OS's, uses the `-all` target. If you want to build them in parallel, use `make -j`. For example, `make -j build-huaweicloud-all`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `huaweicloud`
directory includes several JSON files that define the default configuration for
the different operating systems.

| File | Description |
|------|-------------|
| `ubuntu-2204.json` | The settings for the Ubuntu 22.04 image |


#### Common HuaweiCloud options

This table lists several common options that a user may want to set via
`PACKER_VAR_FILES` to customize their build behavior. This is not an exhaustive
list, and greater explanation can be found in the
[Packer documentation for the HuaweiCloud image builder](https://github.com/huaweicloud/packer-plugin-huaweicloud/wiki).

| Variable | Description | Default |
|----------|-------------|---------|
| `access_key` | The access key for the HuaweiCloud account. | `""` |
| `secret_key` | The secret key for the HuaweiCloud account. | `""` |
| `region`     | The HuaweiCloud region in which to launch the server to create the image. | `"ap-southeast-1g"` |
| `flavor`     | The name for the desired flavor for the server to be created. | `"x1.2u.4g"` |

In the below examples, the parameters can be set via variable file and the use
of `PACKER_VAR_FILES`. See [Customization](../capi.md#customization) for
examples.
