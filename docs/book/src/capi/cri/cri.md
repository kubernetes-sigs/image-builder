# Container Runtime

The image-builder project supports different implementations of CRI, referred to as flavours in this book, as CRI. The preferred option is containerd, but CRI-O is supported for some kind of platforms - depending on cri-o supported operating systems. By default, the built-in CNI provided by CRI-O is disabled. To enable use the following variable:

```json
{
  "crio_disable_default_cni": "false",
}
```

## crictl

When CRI-O is specified, `crictl` is not provided with the installation package. You need to install it using the `http` source type:

```json
{
  "crictl_source_type": "http",
}
```

## Running sandboxed containers using gVisor

As of now, gVisor support is implemented but broken. See [gvisor/issue/3283](https://github.com/google/gvisor/issues/3283). Refer to the [relative section](./customizing-containerd.md) keeping in mind that the variables are similar but different:

```json
{
    "crio_gvisor_runtime": true,
    "crio_gvisor_version": "yyyymmdd", // or "latest"
}
```

For example, you can build the qcow2 image with gVisor enabled with this command:

```sh
PACKER_FLAGS="--var 'crio_gvisor_runtime=true'" make build-qemu-ubuntu-2204-crio
```