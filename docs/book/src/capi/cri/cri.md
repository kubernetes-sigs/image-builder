# Container Runtime

The image-builder project support different implementation, referred as flavour in this book, as CRI. The preferred one is containerd but cri-o is supported for some kind of platforms - depending on cri-o supported operating systems.

## crictl

When cri-o is preferred, crictl is not provided with the package. This means you need to install it using the http source type:

```json
{
  "crictl_source_type": "http",
}
```