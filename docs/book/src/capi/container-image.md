# Using a container image to build a custom image
This image building approach eliminates the need to manually install and maintain pre-requisite packages like Ansible, Packer, libraries etc.
It requires only Docker installed on your machine. All dependencies are handled in Docker while building the container image. This stable container image can be used and reused as a basis for building your own custom images.

Image builder uses GCR to store promoted images in a central registry.
Latest container images can be found here - [Staging](https://gcr.io/k8s-staging-scl-image-builder/cluster-node-image-builder-amd64) and [GA](https://gcr.io/k8s-artifacts-prod/scl-image-builder/cluster-node-image-builder-amd64)

## Building a Container Image

Run the docker build target of Makefile

   ```commandline
   make docker-build
   ```

## Using a Container Image
The latest container image can be pulled from GCR as below -
```commandline
docker pull gcr.io/k8s-staging-scl-image-builder/cluster-node-image-builder-amd64:v0.1.11
```

### Examples

- AMI
    - If the AWS-CLI is already installed on your machine, you can simply mount the `~/.aws` folder that stores all the required credentials.

    ```commandline
    docker run -it --rm -v /Users/<user>/.aws:/home/imagebuilder/.aws k8s.gcr.io/scl-image-builder/cluster-node-image-builder-amd64:v0.1.11 build-ami-ubuntu-2004
    ```
    - Another alternative is to use an `aws-creds.env` file to load the credentials and pass it during docker run.

      ```commandline
      AWS_ACCESS_KEY_ID=xxxxxxx
      AWS_SECRET_ACCESS_KEY=xxxxxxxx
      AWS_DEFAULT_REGION=xxxxxx
      ```

    ```commandline
        docker run -it --rm --env-file aws-creds.env k8s.gcr.io/scl-image-builder/cluster-node-image-builder-amd64:v0.1.11 build-ami-ubuntu-2004
    ```

- AZURE

    - You'll need an `az-creds.env` file to load environment variables `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET`

      ```commandline
      AZURE_SUBSCRIPTION_ID=xxxxxxx
      AZURE_TENANT_ID=xxxxxxx
      AZURE_CLIENT_ID=xxxxxxxx
      AZURE_CLIENT_SECRET=xxxxxx
      ```

    ```commandline
    docker run -it --rm --env-file az-creds.env k8s.gcr.io/scl-image-builder/cluster-node-image-builder-amd64:v0.1.11 build-azure-sig-ubuntu-2004
    ```

- vSphere OVA
    - `vsphere.json` configuration file with user and hypervisor credentials. A template of this file can be found [here](https://github.com/kubernetes-sigs/image-builder/blob/master/images/capi/packer/ova/vsphere.json)

    - Docker's `--net=host` option to ensure http server starts with the host IP and not the docker container IP. This option is Linux specific and thus implies that it can be run only from a Linux machine.

    ```commandline
    docker run -it --rm --net=host --env PACKER_VAR_FILES=/home/imagebuilder/vsphere.json -v <complete path of vsphere.json>:/home/imagebuilder/vsphere.json k8s.gcr.io/scl-image-builder/cluster-node-image-builder-amd64:v0.1.11 build-node-ova-vsphere-ubuntu-2004
    ```

In addition to this, further customizations can be done as discussed [here](./capi.md#customization).
