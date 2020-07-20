# image-builder CLI


### Engines

`image-builder` supports 3 engines for configuring images:

* **qemu** the default builder uses qemu to launch and configure a cloud instance on the local machine
* **packer** provides a wrapper around using packer to launch and configure instances
* **docker** builds images using standard docker images and RUN commands
* **noop** passes the input straght through without configuration, useful for apply [transformations](#transformations-conversions) on existing images

Engines are specified and configured using the `engine` section:

`packer.yaml`
```yaml
engine:
  kind: packer
  version: 1.5.5
  builders:
    amazon-ebs:
      ami_name: !!template image-builder-{{ (time.Now).Format "2006-01-02-150405" }}
      eula: !!template '{{ file.ReadFile "eula.txt" }}'
      access_key: !!env AWS_ACCESS_KEY_ID
      secret_key: !!env AWS_SECRET_ACCESS_KEY
```

### YAML Templating

`image-builder` configs can used the `!!env` and `!!template` YAML directives to replace values inline while still maintaining
YAML compatibility.

The `!!env` directive replaces the KEY with the environment variable.

The `!!template` directive templates out the value using Golang text templates combined with all the functions from the [gomplate](https://docs.gomplate.ca/) library

### OS / Image Combinations
To list the supported OS / Image combinations run `image-builder images`:
The current supported combinations are:

```shell
NAME           OS            DISTRO         RELEASE          VERSION   AMI   QEMU   GCE   AZURE   DOCKER   ISO   OVA
amazonLinux2   amazonLinux   Amazon Linux   Amazon Linux 2   2         ✓
centos7        centos        CentOS         Core             7         ✓                                    ✓
debian8        debian                                                                                       ✓
debian9        debian                                                                                       ✓
ubuntu1804     ubuntu        Ubuntu         bionic           18.04     ✓     ✓            ✓       ✓        ✓
```


### Configuring an image with Kubernetes

```yaml
distroName: ubuntu1804
input:
  kind: qemu
output:
  kind: qemu
kubernetes:
  version: 1.16.9
container_runtime:
  type: containerd
  version: 1.3.4
```

This will build an image using QEMU.


### Customizing an image

Arbitrary konfigadm specs can be combined to further customize an image:

```yaml
packages:
  - nano #ubuntu
  - vi #aws
  - amazon-cli #aws
  - amz-cli #aws amazonLinux
commands:
  - echo Hello Amazon #aws

```

### Transformations / Conversions

`image-builder` can be used to apply arbitrary transformations to images, e.g. to convert a *qcow2* or *raw* disk image to an *ova* run

```shell
image-builder build -c image.yaml`
```

`image.yaml`
```yaml
input:
  kind: img
  url: disk.img
output:
  - kind: vmdk
  - kind: ova
engine:
  kind: noop
```
