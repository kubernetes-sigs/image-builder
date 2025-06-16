# Building CAPI Images for Google Cloud Platform (GCP)

## Prerequisites

### Create Service Account

From your google cloud console, follow [these instructions](https://cloud.google.com/iam/docs/creating-managing-service-accounts#creating)
to create a new service account with Editor permissions. Thereafter, generate a JSON Key and store it somewhere safe.

Use cloud shell to install Ansible, Packer and proceed with building the CAPI compliant VM image.

### Install Ansible and Packer

Start by launching the google cloud shell.

```bash
# Export the GCP project id you want to build images in
$ export GCP_PROJECT_ID=<project-id>

# Export the path to the service account credentials created in the step above
$ export GOOGLE_APPLICATION_CREDENTIALS=</path/to/serviceaccount-key.json>

# If you don't have the image-builder repository
$ git clone https://github.com/kubernetes-sigs/image-builder.git

$ cd image-builder/images/capi/
# Run the target make deps-gce to install Ansible and Packer
$ make deps-gce
```

### Run the Make target to generate GCE images.
From `images/capi` directory, run `make build-gce-ubuntu-<version>` command depending on which ubuntu version you want to build the image for.

For instance, to build an image for `ubuntu 24.04`, run
```bash
$ make build-gce-ubuntu-2404
```

To build all gce ubuntu images, run

```bash
make build-gce-all
```

### Configuration

The `gce` sub-directory inside `images/capi/packer` stores JSON configuration files for Ubuntu OS.

| File | Description
| -------- | --------
| `ubuntu-2204.json`     | Settings for Ubuntu 22.04 image     |
| `ubuntu-2404.json`     | Settings for Ubuntu 24.04 image     |
| `rhel-8.json`     | Settings for RHEL 8 image     |

#### Common GCP options

This table lists several common options that a user may want to set via
`PACKER_VAR_FILES` to customize their build behavior.  This is not an exhaustive
list, and greater explanation can be found in the
[Packer documentation for the Google Cloud Platform builder](https://developer.hashicorp.com/packer/integrations/hashicorp/googlecompute/latest/components/builder/googlecompute).

| Variable       | Description                                                                             | Default             |
|----------------|-----------------------------------------------------------------------------------------|---------------------|
| `zone`         | The GCP zone in which to launch the VM instance.                                        | `null`              |
| `project_id`   | The GCP project ID for the deployment.                                                  | `${GCP_PROJECT_ID}` |
| `machine_type` | The machine type to use for the VM instance (e.g., n1-standard-1, n2-standard-2, etc.). | `"n1-standard-1"`   |

The parameters can be set via variable file and the use
of `PACKER_VAR_FILES`. See [Customization](../capi.md#customization) for
examples.

### List Images

List all images by running the following command in the console

```bash
$ gcloud compute images list --project ${GCP_PROJECT_ID} --no-standard-images

NAME                                         PROJECT            FAMILY                      DEPRECATED  STATUS
cluster-api-ubuntu-2404-v1-17-11-1603233313  myregistry-292303  capi-ubuntu-2404-k8s-v1-17              READY
```

### Delete Images

To delete images from gcloud shell, run following

```bash
$ gcloud compute images delete [image 1] [image2]
```

where `[image 1]` and `[image 2]` refer to the names of the images to be deleted.
