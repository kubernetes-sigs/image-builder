# Build OVAs and AMIs

[build ova instructions](packer/ova/README.md)  
[build ami instructions](packer/ami/README.md)  
  
## Make targets

Check the Makefile to see a list of images may be built

| Targets |
|---------|
| `make build-ova-centos-7` |
| `make build-ova-ubuntu-1804` |
| `make build-ami-default` |

## Configuration

The `packer/config` directory includes several JSON files that define the configuration for the images:

| File | Description |
|------|-------------|
| `packer/config/kubernetes.json` | The version of Kubernetes to install |
| `packer/config/cni.json` | The version of Kubernetes CNI to install |
| `packer/config/containerd.json` | The version of containerd to install |
  
## Output

The OVA images are built and located in `output/BUILD_NAME+kube-KUBERNETES_VERSION`
