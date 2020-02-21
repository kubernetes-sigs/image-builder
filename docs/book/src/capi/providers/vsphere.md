# Building Images for vSphere

## Prerequisites

The `make deps-ova` target will test that Ansible and Packer are installed and available. If they are not, they will be installed to `images/capi/.bin`. This directory will need to be added to your `$PATH`.

### Hypervisor

The images may be built using one of the following hypervisors:

| OS | Builder |
|----|---------|
| Linux | VMware Workstation |
| macOS | VMware Fusion |

The `vmware-iso` builder supports building against a remote VMware ESX server, but is untested with this project.

### Tools

- [Packer](https://www.packer.io/intro/getting-started/install.html)
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.8.0

## The `cloudinit` Directory

The `cloudinit` contains files that:

- **Are** example data used for testing
- Are **not** included in any of the images
- Should **not** be used in production systems

For more information about how the files in the `cloudinit` directory are used, please refer to the section on [accessing the images](#accessing-the-images).

## Building Images

From the `images/capi` directory, run `make build-ova-<OS>`, where `<OS>` is the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `ova` directory includes several JSON files that define the configuration for the images:

| File | Description |
|------|-------------|
| `esx.json` | Additional settings needed when building on a remote ESXi host |
| `ova-centos-7.json` | The settings for the CentOS 7 image |
| `ova-photon-3.json` | The settings for the Photon 3 image |
| `ova-ubuntu-1804.json` | The settings for the Ubuntu 1804 image |


The images are built and located in `images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION`

## Uploading Images

The images are uploaded to the GCS bucket `capv-images`. The path to the image depends on the version of Kubernetes:

| Build type | Upload location |
|------------|-----------------|
| CI | `gs://capv-images/ci/KUBERNETES_VERSION/BUILD_NAME-kube-KUBERNETES_VERSION.ova` |
| Release | `gs://capv-images/release/KUBERNETES_VERSION/BUILD_NAME-kube-KUBERNETES_VERSION.ova` |

Uploading the images requires the `gcloud` and `gsutil` programs, an active Google Cloud account, or a service account with an associated key file. The latter may be specified via the environment variable `KEY_FILE`.

```shell
hack/image-upload.py --key-file KEY_FILE BUILD_DIR
```

First the images are checksummed (SHA256). If a matching checksum already exists remotely then the image is not re-uploaded. Otherwise the images are uploaded to the GCS bucket.

### Listing Available Images

Once uploaded the available images may be listed using the `gsutil` program, for example:

```shell
gsutil ls gs://capv-images/release
```

### Downloading Images

Images may be downloaded via HTTP:

| Build type | Download location |
|------------|-----------------|
| CI | `http://storage.googleapis.com/capv-images/ci/KUBERNETES_VERSION/BUILD_NAME-kube-KUBERNETES_VERSION.ova` |
| Release | `http://storage.googleapis.com/capv-images/release/KUBERNETES_VERSION/BUILD_NAME-kube-KUBERNETES_VERSION.ova` |

## Testing Images

### Accessing the Images

#### Accessing Local VMs

After the images are built, the VMs from they are built are prepped for local testing. Simply boot the VM locally with Fusion or Workstation and the machine will be initialized with cloud-init data from the `cloudinit` directory. The VMs may be accessed via SSH by using the command `hack/image-ssh.sh BUILD_DIR capv`.

#### Accessing Remote VMs

After deploying an image to vSphere, use `hack/image-govc-cloudinit.sh VM` to snapshot the image and update it with cloud-init data from the `cloudinit` directory. Start the VM and now it may be accessed with `ssh -i cloudinit/id_rsa.capi capv@VM_IP`.

### Initialize a CNI

As root:

(copied from [containernetworking/cni](https://github.com/containernetworking/cni#how-do-i-use-cni))

```shell
mkdir -p /etc/cni/net.d
curl -LO https://github.com/containernetworking/plugins/releases/download/v0.7.0/cni-plugins-amd64-v0.7.0.tgz
tar -xzf cni-plugins-amd64-v0.7.0.tgz --directory /etc/cni/net.d
cat >/etc/cni/net.d/10-mynet.conf <<EOF
{
    "cniVersion": "0.2.0",
    "name": "mynet",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "10.22.0.0/16",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ]
    }
}
EOF
cat >/etc/cni/net.d/99-loopback.conf <<EOF
{
    "cniVersion": "0.2.0",
    "name": "lo",
    "type": "loopback"
}
EOF
```

### Run the e2e node conformance tests

As a non-root user:

```shell
curl -LO https://dl.k8s.io/$(</etc/kubernetes-version)/kubernetes-test-linux-amd64.tar.gz
tar -zxvf kubernetes-test-linux-amd64.tar.gz
cd kubernetes/test/bin
sudo ./ginkgo --nodes=8 --flakeAttempts=2 --focus="\[Conformance\]" --skip="\[Flaky\]|\[Serial\]|\[sig-network\]|Container Lifecycle Hook" ./e2e_node.test -- --k8s-bin-dir=/usr/bin --container-runtime=remote --container-runtime-endpoint unix:///var/run/containerd/containerd.sock --container-runtime-process-name /usr/local/bin/containerd --container-runtime-pid-file= --kubelet-flags="--cgroups-per-qos=true --cgroup-root=/ --runtime-cgroups=/system.slice/containerd.service" --extra-log="{\"name\": \"containerd.log\", \"journalctl\": [\"-u\", \"containerd\"]}"
```
