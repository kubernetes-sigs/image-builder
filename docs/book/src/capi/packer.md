# Packer version and Bring Your Own Packer

image-builder uses [HashiCorp Packer](https://www.packer.io) to drive every
image build. The repository **pins Packer to version `1.9.5`**, which is the
last release under the MPL-2.0 license. Beginning with v1.10.0, HashiCorp
relicensed Packer under the Business Source License (BUSL).

`images/capi/hack/ensure-packer.sh` installs the pinned version into
`images/capi/.local/bin` whenever `make deps-*` runs.

## Why the pin?

Kubernetes-sigs projects depend only on open-source-licensed tooling. The
pin to the last MPL-2.0 Packer release lets image-builder continue to be
used and distributed without inheriting the BUSL terms.

## Bring Your Own Packer

You can override the pinned Packer in three ways. These knobs are
recognized by both `hack/ensure-packer.sh` and the `Makefile`, and apply to
every `make build-*` / `make validate-*` target.

| Variable               | Default | Effect                                                                                                                                                                                                                  |
| ---------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PACKER_BIN`           | _unset_ | Absolute path to an existing Packer binary. `ensure-packer.sh` validates it and exits; the `Makefile` uses it for every `packer init`/`build`/`validate`. Highest precedence.                                            |
| `PACKER_VERSION`       | `1.9.5` | Version that `ensure-packer.sh` downloads into `.local/bin` when it manages Packer itself.                                                                                                                               |
| `IB_ALLOW_ANY_PACKER`  | `0`     | Set to `1` to accept whatever `packer` is already on `PATH` instead of having `ensure-packer.sh` replace it with the pinned version. Emits a license warning if the detected Packer is >= 1.10.0 (BUSL).                |

You can also override the binary directly on the `make` command line:

```bash
make PACKER=/opt/packer/packer build-ami-ubuntu-2404
```

### Examples

Use a Packer you already have installed:

```bash
export PACKER_BIN=/usr/local/bin/packer
make deps-azure
make build-azure-sig-ubuntu-2404
```

Use a newer Packer version, downloaded into `.local/bin`:

```bash
export PACKER_VERSION=1.11.2
make deps-ami
make build-ami-ubuntu-2404
```

Accept the Packer that's already on your `PATH` without downgrading it:

```bash
export IB_ALLOW_ANY_PACKER=1
make deps-common
```

### Container image

The same knobs are exposed as `Dockerfile` build args:

```bash
docker build \
  --build-arg PACKER_VERSION=1.11.2 \
  --build-arg IB_ALLOW_ANY_PACKER=1 \
  -t my/image-builder:byo-packer \
  images/capi
```

`PACKER_BIN` is intentionally only a runtime knob — pass it via
`docker run --env PACKER_BIN=/path/in/container/to/packer ...` if you mount
a binary into the container.

## Compatibility notes — please read

* **License**: Using Packer >= 1.10.0 means you accept the BUSL terms.
  image-builder makes no representation about your obligations under that
  license.
* **Plugins**: Each provider's `packer/<provider>/config.pkr.hcl` declares a
  pinned `required_plugins` block. `packer init` resolves those regardless
  of which Packer version you use. Newer Packer releases are generally
  backward compatible with the plugin versions we pin, but specific
  combinations are **not tested by the project's CI**.
* **Support**: Bug reports against builds run with anything other than the
  default Packer (`1.9.5`) are best-effort. If you hit a problem, please
  first try reproducing with the default before opening an issue.
* **`packer init` cache**: If you switch Packer versions mid-checkout you
  may need to clear `~/.packer.d/plugins` or run `packer init -upgrade`
  inside `images/capi` to refresh the local plugin cache.
