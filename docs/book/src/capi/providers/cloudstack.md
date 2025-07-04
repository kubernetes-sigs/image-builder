# Building Images for CloudStack

## Hypervisor

The image is built using KVM hypervisor as a `qcow2` image.
Following which, it can be converted into `ova` for VMware and `vhd` for XenServer.

### Prerequisites for building images

Images can only be built on Linux Machines, and has been tested on Ubuntu 18.04 LTS.
Execute the following command to install qemu-kvm and other packages if you are running Ubuntu 18.04 LTS.

#### Installing packages to use qemu-img

```bash
$ sudo -i
# apt install qemu-kvm libvirt-bin qemu-utils
```

#### Adding your user to the kvm group

```bash
$ sudo usermod -a -G kvm <yourusername>
$ sudo chown root:kvm /dev/kvm
```

Then exit and log back in to make the change take place.

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building cloudstack images are managed by running:

```bash
$ cd image-builder/images/capi
$ make deps-qemu
```

### KVM Hypervisor

From the `images/capi` directory, run `make build-qemu-xxxx-yyyy`. The image is built and located in images/capi/output/BUILD_NAME+kube-KUBERNETES_VERSION. Please replace xxxx with the OS distribution and yyyy with the OS version depending on WHAT you want to build the image for.

For building a ubuntu-2404 based CAPI image, run the following commands -

```bash
$ git clone https://github.com/kubernetes-sigs/image-builder.git
$ cd image-builder/images/capi/
$ cat > extra_vars.json <<EOF
{
  "ansible_user_vars": "provider=cloudstack"
}
EOF
$ PACKER_VAR_FILES=extra_vars.json make clean build-qemu-ubuntu-2404
```

### XenServer Hypervisor

Run the following script to ensure the required dependencies are met :
```bash
$ ./hack/ensure-vhdutil.sh
```

Follow the preceding steps to build the qcow2 CAPI template for KVM. It will display the location of the template to the terminal as shown :
```bash
$ make build-qemu-ubuntu-2404
.............................
Builds finished. The artifacts of successful builds are:
qemu: VM files in directory: ./output/ubuntu-2404-kube-v1.21.10
```
Here the build-name is `ubuntu-2404-kube-v1.21.10`

One completed, run the following commands to convert the template to a XenServer compatible template

```bash
$ ./hack/convert-cloudstack-image.sh ./output/<build-name>/<build-name> x

Creating XenServer Export for ubuntu-2404-kube-v1.21.10
NOTE: For better performance, we will do the overwritten convert!
Done! Convert to ubuntu-2404-kube-v1.21.10.vhd.
Back up source to ubuntu-2404-kube-v1.21.10.vhd.bak.
Converting to ubuntu-2404-kube-v1.21.10-xen.vhd.
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>Done!
Created .vhd file, now zipping
ubuntu-2404-kube-v1.21.10 exported for XenServer: ubuntu-2404-kube-v1.21.10-xen.vhd.bz2
```

### VMware Hypervisor

Run the following script to ensure the required dependencies are met :
```bash
$ ./hack/ensure-ovftool.sh
```

Follow the preceding steps to build the qcow2 CAPI template for KVM. It will display the location of the template to the terminal as shown :
```bash
$ make build-qemu-ubuntu-2404
.............................
Builds finished. The artifacts of successful builds are:
qemu: VM files in directory: ./output/ubuntu-2404-kube-v1.21.10
```
Here the build-name is `ubuntu-2404-kube-v1.21.10`

One completed, run the following commands to convert the template to a VMware compatible template

```bash
$ ./hack/convert-cloudstack-image.sh ./output/<build-name>/<build-name> v

Creating VMware Export for ubuntu-2404-kube-v1.21.10
/usr/bin/ovftool: line 10: warning: setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8): No such file or directory
Opening VMX source: ubuntu-2404-kube-v1.21.10-vmware.vmx
Opening OVA target: ubuntu-2404-kube-v1.21.10-vmware.ova
Writing OVA package: ubuntu-2404-kube-v1.21.10-vmware.ova
Transfer Completed
Completed successfully
```


### Prebuilt Images

For convenience, prebuilt images can be found [here](http://packages.shapeblue.com/cluster-api-provider-cloudstack/images/)
