# Build and deploy machine image on vSphere

This guide outlines the process for using Cluster API (CAPI) to create and manage Kubernetes clusters on vSphere. It is assumed you have an existing CAPI management cluster. Instructions for bootstrapping a management cluster with KIND (Kubernetes inside Docker) can be found in the CAPI quickstart https://cluster-api.sigs.k8s.io/user/quick-start.html

Leveraging Cluster API with your own machine images involves several additional steps:

1. Building a customized machine image for your target provider.
2. Ensuring workload cluster manifests correctly reference the custom machine image.

The following CAPI providers are covered in this guide:

* VMware vSphere
  * machine image type: `OVA` (open virtualization appliance)

Creating machine images from scratch is generally a complex and tedious process. We suggest extending the image-builder project which is used to build example CAPI images. The workflow of image-builder is described below:

  * `packer` is used to boot a temporary "base" VM on the target provider.
  * The temporary VM is provisioned with a set of `ansible` playbooks that preps it for Kubernetes, as well as installs all dependencies including `containerd (runtime)`, `kubeadm`, `kubelet`, `kubectl` and `kubernetes-cni`
  * Container images for `kube-system` componenents such as `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` and `etcd` are pre-pulled.
  * Finally, the temporary VM is shutdown and a machine image is "stamped" from the resulting disk and metadata according to the target provider.

The resulting image is a "pre-baked" machine template that includes everything needed to init or join a Kubernetes cluster when launched.

## Initial setup for building machine images for vSphere

Before building an image on vSphere, you must install the required tools and set up your environment. Note that packer build must be run as a non root user.

1. Install required packer and ansible version. This guide has been tested with `ansible 2.8.5` and `packer v1.4.4`.

    macOS example:
    ```
    brew install packer
    brew install ansible
    ```

1. Clone `image-builder` project into your working directory and checkout the latest release.

    ```
    git clone https://github.com/kubernetes-sigs/image-builder.git
    cd image-builder
    git checkout v0.1.3
    cd images/capi
    ```

Configuration for the Kubernetes components that will be installed inside your machine image can be found at the locations below. This guide will assume the default configurations are used. If you wish to modify the defaults, do not modify the files directly. Override them with your own values by following [these instructions](../capi/capi.md#configuration).

* images/capi/packer/config/cni.json
* images/capi/packer/config/containerd.json
* images/capi/packer/config/kubernetes.json

Now you’re ready to build your vSphere.

## Build OVA machine image for vSphere

Building OVA machine images for vSphere requires several additional tools to be installed:

* VMware Workstation on Linux or VMware Fusion on macOS - The machine images are created on your local workstation first.
* ovftool - This should be installed automatically when workstation or fusion is installed.
* govc - CLI used to upload resulting machine image into target vSphere cluster.

You should make sure that you have those tools installed before continuing.

> Running your build machine inside a vSphere VM is also an option, but you will need to enable nested virtualization, as well as allocate a minimum of 2 CPUs, 4GB of memory, and 30GB Hard disk space. You must also install a desktop and launch VMware workstation at least once before building to complete the setup process.

1. Invoke packer to build your OVA machine image.
`make build-photon-3`

2. The resulting OVA will be located in the packer build directory. Importing the OVA can be done with the vCenter UI as detailed here https://docs.vmware.com/en/VMware-vSphere/6.5/com.vmware.vsphere.vm_admin.doc/GUID-17BEDA21-43F6-41F4-8FB2-E01D275FE9B4.html.

Alternatively you can import the OVA with the govc CLI. More details can be found here

```
Usage: govc import.ova [OPTIONS] PATH_TO_OVA
```

## Deploying your cluster - manifest modifications

At this point your machine image should be built and stored inside your target provider. You may now create or generate your workload cluster manifests as you normally would. More details on generating these can be found in the quickstart. Before you deploy, you will need to make a few modifications to your cluster manifests to properly reference your machine image.

1. If you are using vSphere, confirm `template` matches uploaded machine image. The generated manifests should specify `template:<TEMPLATE_NAME>`. This name should match the OVA template name when it was uploaded after build. Example below.

```
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha2
kind: VSphereMachine
metadata:
  labels:
    cluster.x-k8s.io/cluster-name: capi-quickstart
    cluster.x-k8s.io/control-plane: "true"
  name: capi-quickstart-controlplane-0
  namespace: default
spec:
  datacenter: SDDC-Datacenter
  diskGiB: 50
  memoryMiB: 2048
  network:
    devices:
    - dhcp4: true
      dhcp6: false
      networkName: vm-network-1
  numCPUs: 2
  template: <UPLOADED OVA TEMPLATE NAME>
```

## Ready to Deploy
You are now ready to deploy! Apply your cluster manifests as you normally would according to the CAPI quickstart. Your workload cluster should now be using the images you have built.
