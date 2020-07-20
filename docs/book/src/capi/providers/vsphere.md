# Building Images for vSphere

## Prerequisites

The `make deps-ova` target will test that Ansible and Packer are installed and available. If they are not, they will be installed to `images/capi/.bin`. This directory will need to be added to your `$PATH`.

### Hypervisor

The images may be built using one of the following hypervisors:

| OS | Builder | Build target |
|----|---------|--------------|
| Linux | VMware Workstation | build-node-ova-local-<OS> |
| macOS | VMware Fusion | build-node-ova-local-<OS> |
| ESXi | ESXi | build-node-ova-esx-<OS> |
| vSphere | vSphere >= 6.5 | build-node-ova-vsphere-<OS> |

**NOTE** If you want to build all available OS's, uses the `-all` target. If you want to build them in parallel, use `make -j`. For example, `make -j build-node-ova-local-all`.

The `esxi` builder supports building against a remote VMware ESX server with [specific configuration](https://packer.io/docs/builders/vmware-iso.html#building-on-a-remote-vsphere-hypervisor) (ssh access), but is untested with this project.
The `vsphere` builder supports building against a remote VMware vSphere using standard API.


### Prerequisites for all images

- [Packer](https://www.packer.io/intro/getting-started/install.html) version >= 1.5.5
- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html) version >= 2.8.0

### Prerequisites for vSphere builder

Packer version >= 1.6.0 is required (older versions still work for building from remote ESXi and locally options).

Complete the `vsphere.json` configuration file with credentials and informations specific to the remote vSphere hypervisor used to build the `ova` file.
This file must have the following format (`cluster` can be replace by `host`):
```
{
    "vcenter_server":"FQDN of vcenter",
    "username":"vcenter_username",
    "password":"vcenter_password",
    "datastore":"template_datastore",
    "folder": "template_folder_on_vcenter",
    "cluster": "esxi_cluster_used_for_template_creation",
    "network": "network_attached_to_template",
    "insecure_connection": "false"
}
```

If you prefer to use a different configuration file, you can create it with the same format and export `PACKER_VAR_FILES` environment variable containing the full path to it.

## Building Images

From the `images/capi` directory, run `make build-node-ova-<hypervisor>-<OS>`, where `<hypervisor>` is your target hypervisor (`local`, `vsphere` or `esx`) and `<OS>` is the desired operating system. The available choices are listed via `make help`.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `ova` directory includes several JSON files that define the configuration for the images:

| File | Description |
|------|-------------|
| `esx.json` | Additional settings needed when building on a remote ESXi host |
| `centos-7.json` | The settings for the CentOS 7 image |
| `photon-3.json` | The settings for the Photon 3 image |
| `ubuntu-1804.json` | The settings for the Ubuntu 18.04 image |
| `ubuntu-2004.json` | The settings for the Ubuntu 20.04 image |
| `vsphere.json` | Additional settings needed when building on a remote vSphere |


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
This hack necessitate the `govc` utility from [VMmare](https://github.com/vmware/govmomi/tree/master/govc)

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

## The `cloudinit` Directory

The `cloudinit` contains files that:

- **Are** example data used for testing
- Are **not** included in any of the images
- Should **not** be used in production systems

For more information about how the files in the `cloudinit` directory are used, please refer to the section on [accessing the images](#accessing-the-images).
