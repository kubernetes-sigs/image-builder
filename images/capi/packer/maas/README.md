To build an image using a specific version of Kubernetes use the "PACKER_FLAGS" env var like in the example below:

PACKER_FLAGS="--var 'kubernetes_rpm_version=1.30.5' --var 'kubernetes_semver=v1.30.5' --var 'kubernetes_series=v1.30' --var 'kubernetes_deb_version=1.30.5-1.1'" make build-maas-ubuntu-2204-efi

P.S: In order to change disk size(defaults to 20GB as of 31.10.22) you can update PACKER_FLAGS with:
--var 'disk_size=<disk size in mb>'


Upload images to MaaS

```
maas <PROFILE> boot-resources create name=custom/<IMAGE NAME> architecture=amd64/generic title=<IMAGE NAME> subarches=generic base_image=ubuntu/<SEE NOTES> content@=./<FILE>.tar.gz
```

Notes / Things you need to known:

- If you are using ubuntu **22.04**, set the `base_image` field to: `ubuntu/jammy`. For 24.04, use: `ubuntu/noble`
- Use **UEFI** to boot the machines, if you use BIOS, your MaaS deployment will **probably** fail.