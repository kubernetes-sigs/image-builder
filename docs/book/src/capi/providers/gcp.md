# Building Images for Google Cloud Platform (GCP)

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

### Build Cluster API Compliant VM Image

```bash
# clone the image-builder repo if you haven't already
$ git clone https://sigs.k8s.io/image-builder.git image-builder

$ cd image-builder/images/capi/

# Run the Make target to generate GCE images.
$ make build-gce-default

# List images
$ gcloud compute images list --project ${GCP_PROJECT_ID} --no-standard-images

NAME                                         PROJECT                FAMILY                      DEPRECATED  STATUS
cluster-api-ubuntu-1804-v1-16-14-1599066516  virtual-anchor-281401  capi-ubuntu-1804-k8s-v1-16              READY
```
