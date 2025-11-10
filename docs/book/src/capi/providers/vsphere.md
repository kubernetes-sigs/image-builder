# Building Images for vSphere

## Hypervisor

The images may be built using one of the following hypervisors:

| OS            | Builder                         | Build target                      |
| ------------- | ------------------------------- | --------------------------------- |
| Linux         | VMware Workstation (vmware-iso) | build-node-ova-local-<OS>         |
| macOS         | VMware Fusion (vmware-iso)      | build-node-ova-local-<OS>         |
| vSphere       | vSphere >= 6.5                  | build-node-ova-vsphere-<OS>       |
| vSphere       | vSphere >= 6.5                  | build-node-ova-vsphere-base-<OS>  |
| vSphere Clone | vSphere >= 6.5                  | build-node-ova-vsphere-clone-<OS> |
| Linux         | VMware Workstation (vmware-vmx) | build-node-ova-local-vmx-<OS>     |
| macOS         | VMware Fusion (vmware-vmx)      | build-node-ova-local-vmx-<OS>     |

**NOTE** If you want to build all available OS's, uses the `-all` target. If you want to build them in parallel, use `make -j`. For example, `make -j build-node-ova-local-all`.

The `vsphere` builder supports building against a remote VMware vSphere using standard API.

### vmware-vmx builder
During the dev process it's uncommon for the base OS image to change, but the image building process builds the base image from the ISO every time and thus adding a significant amount of time to the build process.

To reduce the image building times during development, one can use the `build-node-ova-local-base-<OS>` target to build the base image from the ISO. By setting `source_path` variable in `vmx.json` to the `*.vmx` file from the output, it can then be re-used with the `build-node-ova-local-vmx-<OS>` build target to speed up the process.


### vsphere-clone builder
`vsphere-base` builder allows you to build one time base OVAs from iso images using the kickstart process. It leaves the user `builder` intact in base OVA to be used by clone builder later. `vSphere-clone` builder builds on top of base OVA by cloning it and ansiblizing it.
This saves time by allowing repeated iteration on base OVA without installing OS from scratch again and again. Also, it uses link cloning and `create_snapshot` feature to clone faster.

### Prerequisites for vSphere builder

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
    "insecure_connection": "false",
    "template": "base_template_used_by_clone_builder",
    "create_snapshot": "creates a snaphot on base OVA after building",
    "linked_clone": "Uses link cloning in vsphere-clone builder: true, by default"
}
```

If you prefer to use a different configuration file, you can create it with the same format and export `PACKER_VAR_FILES` environment variable containing the full path to it.

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building OVAs are managed by running:

```bash
make deps-ova
```

From the `images/capi` directory, run `make build-node-ova-<hypervisor>-<OS>`, where `<hypervisor>` is your target hypervisor (`local` or `vsphere`) and `<OS>` is the desired operating system. The available choices are listed via `make help`.

### OVA Creation

When the final OVA is created, there are two methods that can be used for creation. By default, an OVF file is created, the manifest is created using SHA256 sums of the OVF and VMDK, and then `tar` is used to create an OVA containing the OVF, VMDK, and the manifest.

Optionally, `ovftool` can be used to create the OVA. This has the advantage of validating the created OVF, and has greater chances of producing OVAs that are compliant with more versions of VMware targets of Fusion, Workstation, and vSphere. To use `ovftool` for OVA creation, set the env variable IB_OVFTOOL to any non-empty value. Optionally, args to `ovftool` can be passed by setting the env var IB_OVFTOOL_ARGS like the following:

```bash
IB_OVFTOOL=1 IB_OVFTOOL_ARGS="--allowExtraConfig" make build-node-ova-<hypervisor>-<OS>
```

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `ova` directory includes several JSON files that define the configuration for the images:

| File               | Description                                                  |
|--------------------|--------------------------------------------------------------|
| `flatcar.json`     | The settings for the Flatcar image                           |
| `photon-4.json`    | The settings for the Photon 4 image                          |
| `rhel-8.json`      | The settings for the RHEL 8 image                            |
| `rhel-9.json`      | The settings for the RHEL 9 image                            |
| `ubuntu-2204.json` | The settings for the Ubuntu 22.04 image                      |
| `ubuntu-2204-efi.json` | The settings for the Ubuntu 22.04 EFI image                      |
| `ubuntu-2404.json` | The settings for the Ubuntu 24.04 image                      |
| `ubuntu-2404-efi.json` | The settings for the Ubuntu 24.04 EFI image                      |
| `vsphere.json`     | Additional settings needed when building on a remote vSphere |

### Photon specific options

#### Enabling .local lookups via DNS

Photon uses systemd-resolved defaults, which means that .local will be resolved using Multicast DNS. If you are deploying to
an environment where you require DNS resolution .local, then add `leak_local_mdns_to_dns=yes` in `ansible_user_vars`.

### RHEL

When building the RHEL image, the OS must register itself with the Red Hat Subscription Manager (RHSM). To do this, the current supported method is to supply a username and password via environment variables. The two environment variables are `RHSM_USER` and `RHSM_PASS`. Although building RHEL images has been tested via this method, if an error is encountered during the build, the VM is deleted without the machine being unregistered with RHSM. To prevent this, it is recommended to build with the following command:

```shell
PACKER_FLAGS=-on-error=ask RHSM_USER=user RHSM_PASS=pass make build-node-ova-<hypervisor>-rhel-9
```

The addition of `PACKER_FLAGS=-on-error=ask` means that if an error is encountered, the build will pause, allowing you to SSH into the machine and unregister manually.

### Output

The images are built and located in `images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION`

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
