# Quick Start

In this tutorial we will cover the basics of how to download and execute the Image Builder.

## Installation

As a set of scripts and Makefiles that rely on Packer and Ansible, there is image builder binary/application to install. Rather we need to download the tooling from the GitHub repo and make sure that the Packer and Ansible are installed.

To get the latest image-builder source on your machine, execute the following:

```sh
curl -L https://github.com/kubernetes-sigs/image-builder/tarball/master -o image-builder.tgz
tar xzf image-builder.tgz
cd image-builder/images/capi
```

## Dependencies

Once you are within the `capi` directory, you can execute `make` or `make help` to see all the possible make targets. Before we can build an image, we need to make sure that Packer and Ansible are installed on your system. You may already have them, Mac users may have them installed via `brew`, or you may have downloaded them directly.

If you want the image-builder to install these tools for you, they can be installed by executing `make deps`. This will install dependencies into `image-builder/images/capi/.bin` **if they are not already on your system**. `make deps` will first check if Ansible and Packer are available and if they are, will use the existing installations.

Looking at the output from `make deps`, if Ansible or Packer were installed into the `.bin` directory, you'll need to add that to your `PATH` environment variable before they can be used. Assuming you are still in `images/capi`, you can do that with the following:

```sh
export PATH=$PWD/.bin:$PATH
```

## Builds

With the CAPI image builder installed and dependencies satisfied, you are now ready to build an image. In general, this is done via `make` targets, and each provider (e.g. AWS, GCE, etc.) will have different requirements for what information needs to be provided (such as cloud provider authentication credentials). Certain providers may have dependencies that are not satisfied by `make deps`, for example the vSphere provider needs access to a hypervisor (VMware Fusion on macOS, VMware Workstation on Linux). See the [specific documentation](./capi.md#providers) for your desired provider for more details.
