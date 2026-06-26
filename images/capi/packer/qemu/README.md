To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

PACKER_FLAGS="--var 'kubernetes_rpm_version=1.28.3' --var 'kubernetes_semver=v1.28.3' --var 'kubernetes_series=v1.28' --var 'kubernetes_deb_version=1.28.3-1.1'" make build-kubevirt-qemu-ubuntu-2404

P.S: In order to change disk size(defaults to 20GB as of 31.10.22) you can update PACKER_FLAGS with:
--var 'disk_size=<disk size in mb>'

Ubuntu autoinstall builds use the `ubuntu_repo` and `ubuntu_security_repo` Packer variables while rendering the installer user-data. For example:

PACKER_FLAGS="--var 'ubuntu_repo=http://mirror.example.com/ubuntu' --var 'ubuntu_security_repo=http://security.example.com/ubuntu'" make build-qemu-ubuntu-2404
