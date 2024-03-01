# Container Runtime

The image-builder project support different implementation, referred as flavour in this book, as CRI. The preferred one is containerd but cri-o is supported for some kind of platforms - depending on cri-o supported operating systems.

## crictl

When cri-o is preferred, crictl is not provided with the package. This means you need to install it using the http source type:

```json
{
  "crictl_source_type": "http",
}
```

## Running sandboxed containers using gVisor

As of now gVisor support is implemented but broken - [gvisor/issue/3283](https://github.com/google/gvisor/issues/3283). Refer to the [relative section](./customizing-containerd.md) keeping in mind that the variables are similar but different:

```json
{
    "crio_gvisor_runtime": "true",
    "crio_gvisor_version": "yyyymmdd", // or latest
}
```

For example you can build the qcow2 image with gvisor enabled with this snippet:

```sh
PACKER_FLAGS="--var 'crio_gvisor_runtime=\"true\"'" make build-qemu-ubuntu-2204-crio
```