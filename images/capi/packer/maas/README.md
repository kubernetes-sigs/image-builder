# Prereqs

Assuming you're building on Ubuntu:
```
apt update
apt install -y make jq unzip python3-pip
cd images/capi
make deps-qemu
```

If you will be building ARM64 images, ensure you run the builder on a native ARM64 server and add these additional prereqs:
```
apt-get install qemu-system-arm libvirt-daemon-system -y

# create EFI disk images for ARM64
pushd /var/lib/libvirt/images/
dd if=/dev/zero of=capi.fd bs=1M count=64
dd if=/dev/zero of=capi-nvmram.fd bs=1M count=64
dd if=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd of=capi.fd conv=notrunc
popd
```

# Building

To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

For AMD64:
```
export PATH=/root/.local/bin:$PATH

PACKER_FLAGS="--var 'kubernetes_rpm_version=1.30.5' --var 'kubernetes_semver=v1.30.5' --var 'kubernetes_series=v1.30' --var 'kubernetes_deb_version=1.30.5-1.1'" make build-maas-ubuntu-2204-efi
```

For ARM64:
```
export PATH=/root/.local/bin:$PATH

ARCH=arm64 PACKER_FLAGS="--var 'kubernetes_rpm_version=1.30.5' --var 'kubernetes_semver=v1.30.5' --var 'kubernetes_series=v1.30' --var 'kubernetes_deb_version=1.30.5-1.1'" make build-maas-ubuntu-2204-arm64
```

P.S: In order to change disk size(defaults to 20GB as of 31.10.22) you can update PACKER_FLAGS with:
--var 'disk_size=<disk size in mb>'

# Uploading to MaaS

To upload the generates images to MaaS, run the following command.

For AMD64:
```
maas <PROFILE> boot-resources create name=<IMAGE NAME> architecture=amd64/generic title=<IMAGE NAME> base_image=ubuntu/<SEE NOTES> content@=./<FILE>.tar.gz
```

For ARM64:
```
maas <PROFILE> boot-resources create name=<IMAGE NAME> architecture=arm64/generic title=<IMAGE NAME> base_image=ubuntu/<SEE NOTES> content@=./<FILE>.tar.gz
```


Notes / Things you need to known:

- If you are using ubuntu **22.04**, set the `base_image` field to: `ubuntu/jammy`. For 24.04, use: `ubuntu/noble`
- Use **UEFI** to boot the machines, if you use BIOS, your MaaS deployment will **probably** fail.