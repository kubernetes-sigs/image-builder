# Image building via containers

** This tooling is experimental and likely to change, or may be removed in future**

These tools let us construct the primary contents of a disk image
using docker (or compatible tools), and then we can convert them to a
raw disk images.  We add a partition table and boot loader; the
container image populates the primary partition.

It also includes some tools for uploading raw images to clouds.  These
will likely be subsumed into the imagebuilder CLI work.

## Structure

The `images` directory contains the image specifications.  Because
we're using docker, these are just Dockerfiles and the supporting
files we want to add to the images.

The `tools` directory contains the scripts for converting docker
images to raw disk images, and for uploading raw disk images to clouds
(currently AWS and GCP).

The `cloud` directory contains some terraform configurations for
running test instances using our images on EC2 and on GCE; it also
contains the configuration for a "worker instance" used to upload
images to AWS.  Because it's terraform it's relatively easy to
understand and change.

## Trying it out with qemu

If you're on linux, it's easy to try this out locally using qemu.

Note: this image has a root password of "root", and is thus suitable
only for local testing.

```
# Build the container image for 'buster-qemu', by running docker build
make -C images buster-qemu

# Convert the container image to a raw disk image
tools/container-to-raw buster-qemu

# Try it out in qemu
qemu-img create -f qcow2 -o backing_file=buster-qemu.raw workspace/test.img 20G
qemu-system-x86_64 -nographic -serial mon:stdio \
  -netdev user,id=net0,net=192.168.76.0/24,dhcpstart=192.168.76.9 \
  -device e1000,netdev=net0 \
  -drive file=workspace/test.img \
  -m 512 --enable-kvm

# To login, use username: root and password: root (defined in the buster-qemu image)

# To quit: type Control-a and c to enter monitor mode, type "quit"

rm workspace/test.img
```

## Build and upload an AWS image

It isn't much harder to build an image for AWS, and there's a
convenient tool to upload the image to AWS.

```
# Build the container image for 'buster-aws', by running docker build
make -C images buster-aws

# Convert the container image to a raw disk image
tools/container-to-raw buster-aws

# Copy your SSH public key to be used with terraform
cp ~/.ssh/id_rsa.pub cloud/aws-upload/

# Create a worker instance in AWS; we upload the raw disk to it
pushd cloud/aws-upload
terraform init
terraform apply
WORKER_INSTANCE_ID=`terraform output worker_instance_id`
popd

# Upload to AWS
tools/upload-to-aws buster-aws us-east-2 ${WORKER_INSTANCE_ID}

# Cleanup the builder
pushd cloud/aws-upload
terraform destroy
popd
```

To test the AWS image:

```
# Copy your SSH public key to be used with terraform
cp ~/.ssh/id_rsa.pub cloud/aws-test/

# Create a test instance in AWS
pushd cloud/aws-test
terraform init
terraform apply
TEST_INSTANCE_PUBLIC_IP=`terraform output test_instance_public_ip`
TEST_INSTANCE_ID=`terraform output test_instance_id`
TEST_INSTANCE_REGION=`terraform output test_instance_region`
popd

# If running in a script, it can be useful to wait for the instance to be ready
aws ec2 wait instance-status-ok --instance-id ${TEST_INSTANCE_ID} --region ${TEST_INSTANCE_REGION}

# SSH to the instance and test it out
ssh admin@${TEST_INSTANCE_PUBLIC_IP}

# Cleanup the test builder
pushd cloud/aws-test
terraform destroy
popd
```


## Build and upload a GCE image

This follows the same pattern as AWS, though the image upload is a
little simpler on GCE - it doesn't need a worker instance.

```
# Build the container image for 'buster-gce', by running docker build
make -C images buster-gce

# Convert the container image to a raw disk image
tools/container-to-raw buster-gce

# Create a bucket to upload the images to
PROJECT=`gcloud config get-value project`
BUCKET=${PROJECT}-images

gsutil mb gs://${BUCKET} || true

# Upload to GCE and register as an image
tools/upload-to-gce buster-gce gs://${BUCKET}
```

To test the GCE image:

```
# Create a worker instance in GCE
pushd cloud/gce-test
terraform init
terraform apply --var google_project=$(gcloud config get-value project)
TEST_INSTANCE_NAME=`terraform output test_instance_name`
TEST_INSTANCE_ZONE=`terraform output test_instance_zone`
popd

# SSH to the instance and test it out
gcloud compute ssh ${TEST_INSTANCE_NAME} --zone ${TEST_INSTANCE_ZONE}

# Cleanup the test builder
pushd cloud/gce-test
terraform destroy --var google_project=$(gcloud config get-value project)
popd
```

An Google Cloud Build configuration is also provided; it can build and
register images in GCE automatically.
