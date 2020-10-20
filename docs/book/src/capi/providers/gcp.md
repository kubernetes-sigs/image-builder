# Building CAPI Images for Google Cloud Platform (GCP)

## Prerequisites

### Create Service Account

From your google cloud console, follow [these instructions](https://cloud.google.com/iam/docs/creating-managing-service-accounts#creating)
to create a new service account with Editor permissions. Thereafter, generate a JSON Key and store it somewhere safe. 

Use cloud shell to install ansible, packer and proceed with building the CAPI compliant vm image.

### Install Ansible and Packer

Start by launching the google cloud shell.

```bash
# Export the GCP project id you want to build images in
$ export GCP_PROJECT_ID=<project-id>

# Export the path to the service account credentials created in the step above
$ export GOOGLE_APPLICATION_CREDENTIALS=</path/to/serviceaccount-key.json>

$ git clone https://sigs.k8s.io/image-builder.git image-builder

$ cd image-builder/images/capi/

# Run the target make deps-gce to install ansible and packer
$ make deps-gce
```

## Build Cluster API Compliant VM Image

```bash
# clone the image-builder repo if you haven't already
$ git clone https://sigs.k8s.io/image-builder.git image-builder

$ cd image-builder/images/capi/
```

### Run the Make target to generate GCE images.
From `images/capi` directory, run `make build-gce-ubuntu-<version>` command depending on which ubuntu version you want to build the image for.

For instance, to build an image for `ubuntu 18-04`, run 
```bash
$ make build-gce-ubuntu-1804
```

To build all gce ubuntu images, run

```bash
make build-gce-all
```

### Configuration

The `gce` sub-directory inside `images/capi/packer` stores JSON configuration files for Ubuntu OS.



| File | Description 
| -------- | --------
| `ubuntu-1804.json`     | Settings for Ubuntu 18-04 image     |
| `ubuntu-2004.json`     | Settings for Ubuntu 20-04 image     |


### List Images

List all images by running the following command in the console
```bash
$ gcloud compute images list --project ${GCP_PROJECT_ID} --no-standard-images

NAME                                         PROJECT            FAMILY                      DEPRECATED  STATUS
cluster-api-ubuntu-1804-v1-17-11-1603233313  myregistry-292303  capi-ubuntu-1804-k8s-v1-17              READY
cluster-api-ubuntu-2004-v1-17-11-1603233874  myregistry-292303  capi-ubuntu-2004-k8s-v1-17              READY
```

### Delete Images

To delete images from gcloud shell, run following

```bash
$ gcloud compute images delete [image 1] [image2]
```
where `[image 1]` and `[image 2]` refer to the names of the images to be deleted.