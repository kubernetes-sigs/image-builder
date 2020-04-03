# Build and deploy machine image on AWS

This guide outlines the process for using Cluster API (CAPI) to create and manage Kubernetes clusters on AWS. It is assumed you have an existing CAPI management cluster. Instructions for bootstrapping a management cluster with KIND (Kubernetes inside Docker) can be found in the CAPI quickstart https://cluster-api.sigs.k8s.io/user/quick-start.html

Leveraging Cluster API with your own machine images involves several additional steps:

1. Building a customized machine image for your target provider.
2. Ensuring workload cluster manifests correctly reference the custom machine image.

The following CAPI providers are covered in this guide:

* Amazon Web Services
  * machine image type: `AMI` (Amazon Machine Image)

Creating machine images from scratch is generally a complex and tedious process. We suggest extending the image-builder project which is used to build example CAPI images. The workflow of image-builder is described below:

  * `packer` is used to boot a temporary "base" VM on the target provider.
  * The temporary VM is provisioned with a set of `ansible` playbooks that preps it for Kubernetes, as well as installs all dependencies including `containerd (runtime)`, `kubeadm`, `kubelet`, `kubectl` and `kubernetes-cni`
  * Container images for `kube-system` componenents such as `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` and `etcd` are pre-pulled.
  * Finally, the temporary VM is shutdown and a machine image is "stamped" from the resulting disk and metadata according to the target provider.

The resulting image is a "pre-baked" machine template that includes everything needed to init or join a Kubernetes cluster when launched.

## Initial setup for building machine images for AWS

Before building an image on AWS, you must install the required tools and set up your environment. Note that packer build must be run as a non root user.

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

Now you’re ready to build your AWS image.

## Build AMI machine image for AWS

1. To build AMI machine images for AWS you must also install an additional packer plugin, goss. Packer will look for it in the same directory as our configuration files.

```
# linux
wget https://github.com/YaleUniversity/packer-provisioner-goss/releases/download/v0.3.0/packer-provisioner-goss-v0.3.0-linux-amd64 mv packer-provisioner-goss-v0.3.0-linux-amd64 packer-provisioner-goss chmod +x packer-provisioner-goss
# macos
wget https://github.com/YaleUniversity/packer-provisioner-goss/releases/download/v0.3.0/packer-provisioner-goss-v0.3.0-darwin-amd64 mv packer-provisioner-goss-v0.3.0-linux-amd64 packer-provisioner-goss chmod +x packer-provisioner-goss
```

2. Configure images/capi/packer/ami/packer.json

* `aws_access_key` and aws_secret_key with your AWS credentials.
* `aws_region` for the target region you want to build your AMI in, for example us-west-2
* `ami_regions` with a comma-separated list of regions you want to copy the resulting AMI to. You can only deploy a cluster in the region where the AMI exists.

* Building private AMIs
  * `ami_groups` by default is set to all. This will effectively publish the ami so any AWS user can deploy it in their own account if they know the ami-id. The script below is set to null to prevent this, You can also set the `-var ami_groups=""` and `-var snapshot_groups=""` parameters `PACKER_FLAGS` to ensure you end up with a private AMI.

3. Build the AMI with `PACKER_FLAGS="-only=ubuntu-1804" make build-ami-default`  Take note of the AMI-ID for each specified region that is printed when image building is complete. You will need to reference that when you deploy your workload cluster.


## Deploying your cluster - manifest modifications

At this point your machine image should be built and stored inside your target provider. You may now create or generate your workload cluster manifests as you normally would. More details on generating these can be found in the quickstart. Before you deploy, you will need to make a few modifications to your cluster manifests to properly reference your machine image.

1. If you are using AWS, update the `AWSMachine` spec with `AMI-ID` inside both controlplane.yaml and machine-deployment.yaml. The AMI-ID will not exist in the manifests by default, ensure you specify the correct AMI-ID for the region you are deploying to.
Example below:

```
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha2
kind: AWSMachine
metadata:
  name: capa-controlplane
spec:
  ami:
    id: <AMI-ID>
  iamInstanceProfile: control-plane.cluster-api-provider-aws.sigs.k8s.io
  instanceType: t3.medium
  rootDeviceSize: 20
  sshKeyName: default
```

## Ready to Deploy
You are now ready to deploy! Apply your cluster manifests as you normally would according to the CAPI quickstart. Your workload cluster should now be using the images you have built.
