# Building Images for MaaS

The image is built using the KVM hypervisor (QEMU).

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` to create QEMU images are installed with:

```bash
cd image-builder
make deps-qemu
```

## Building a MaaS Image

From the `image-builder` directory, run:

```bash
make build-maas-ubuntu-xxxx-efi
```

The image will be located in `images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION`. Replace `xxxx` with `2204` or `2404`, depending on the Ubuntu version.

To build a Ubuntu 22.04-based CAPI image:

```bash
git clone https://github.com/kubernetes-sigs/image-builder.git
cd image-builder
make build-qemu-ubuntu-2204-efi
```

## Uploading to MaaS

### Prerequisites

- Ubuntu 22.04 (required for the MaaS client)
- Command-line MaaS client installed

### Installing the MaaS Client

```bash
apt update && apt install -y tzdata software-properties-common
apt-add-repository -y ppa:maas/3.5
apt install -y maas-cli python3-openssl
```

### Logging into MaaS

```bash
maas login admin <MAAS_HTTP_ENDPOINT>/MAAS/ '<TOKEN>'
```

#### Creating a Token

Log into the MaaS interface, go to your preferences (your username), click "API Keys," and copy an existing key or generate a new one.

### Uploading the Image

Navigate to `images/capi/output/`, find the generated image, and enter its directory. Inside, you will see two files:

```bash
cd images/capi/output/ubuntu-2204-efi-kube-v1.30.5/

ls -l
total 7165084
-rw-r--r-- 1 vasartori vasartori 5132255232 Feb 25 08:33 ubuntu-2204-efi-kube-v1.30.5
-rw-r--r-- 1 root      root      2203701699 Feb 25 08:33 ubuntu-2204-efi-kube-v1.30.5.tar.gz
```

Use the **.tar.gz** file for the upload:

```bash
maas admin boot-resources create name=custom/your-image architecture=amd64/generic title=your-image subarches=generic base_image=ubuntu/jammy content@=./ubuntu-2204-efi-kube-v1.30.5.tar.gz
```

**Note:** Set `base_image=ubuntu/jammy` for Ubuntu 22.04 or `ubuntu/noble` for 24.04.

## Custom Curtin Scripts
If you need to override the default MaaS curtin scripts, create a custom role containing the curtin hooks. The files must be copied to the `/curtin` directory

For more information on how to create and use custom roles, refer to the official documentation: https://image-builder.sigs.k8s.io/capi/capi#customization

## iSCSI configuration note:

If you need unique names for the iSCSI InitiatorName, add a KubeadmConfigTemplate and include the following command under `spec.template.spec.preKubeadmCommands`

```bash
echo "InitiatorName=$(iscsi-iname -p iqn.2004-10.com.ubuntu:$(cat /etc/hostname))" > /etc/iscsi/initiatorname.iscsi
```

### Example

```yaml
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: t-cluster-md-0
  namespace: default
spec:
  template:
    spec:
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            event-qps: "0"
            feature-gates: RotateKubeletServerCertificate=true
            read-only-port: "0"
          name: '{{ v1.local_hostname }}'
      preKubeadmCommands:
      - echo "InitiatorName=$(iscsi-iname -p iqn.2004-10.com.ubuntu:$(cat /etc/hostname))" > /etc/iscsi/initiatorname.iscsi
      - systemctl restart open-iscsi
      - while [ ! -S /var/run/containerd/containerd.sock ]; do echo 'Waiting for containerd...';
        sleep 1; done
      - sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab
      - swapoff -a
      useExperimentalRetryJoin: true
```
