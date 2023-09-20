To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

```
PACKER_FLAGS="--var 'kubernetes_rpm_version=1.27.3-0' --var 'kubernetes_semver=v1.27.3' --var 'kubernetes_series=v1.27' --var 'kubernetes_deb_version=1.27.3-00'" make build-proxmox-ubuntu-2204
```
