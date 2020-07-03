ImageBuilder
============

ImageBuilder is a tool for building an optimized k8s images, currently only
supporting AWS.

Please also see the `README` in the `templates` folder for documentation as to
the motivation for building a custom image.

It is a wrapper around `bootstrap-vz`, which is the tool used to build official
Debian cloud images.  

It adds functionality to spin up an instance for building the image, and
publishing the image to all regions.

Imagebuilder:

* reads a config file (eg. `aws-1.11-stretch.yaml`)
* creates an instance to build the image
* builds the image as specified by `TemplatePath` in the config file
* makes the image public if image publishing was enabled (it is, by default)
* (AWS only) replicates the image to all accessible regions if replication was enabled (it is, by default)
* and then shuts down the builder instance. 

These stages can be controlled through either flags or config file options,
depending on the stage.

For example, you might want to use `--publish=false` for an internal image.

## AWS

* `export AWS_PROFILE=...` if you are not using the default profile.
 (or generate a new account & use `export AWS_ACCESS_KEY_ID` and `export AWS_SECRET_ACCESS_KEY`)
* Create a VPC (with a subnet) and tag the subnet with `k8s.io/role/imagebuilder=1`
* Create a security group in the VPC, allowing port 22, and tag with `k8s.io/role/imagebuilder=1`
* The following commands are scripted in hack/setup-aws.sh

```
VPC_ID=`aws ec2 create-vpc --cidr-block 172.20.0.0/16 --query Vpc.VpcId --output text`
aws ec2 create-tags --resources ${VPC_ID} --tags Key=k8s.io/role/imagebuilder,Value=1

SUBNET_ID=`aws ec2 create-subnet --cidr-block 172.20.1.0/24 --vpc-id ${VPC_ID} --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources ${SUBNET_ID} --tags Key=k8s.io/role/imagebuilder,Value=1

IGW_ID=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
aws ec2 create-tags --resources ${IGW_ID} --tags Key=k8s.io/role/imagebuilder,Value=1

aws ec2 attach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID}

RT_ID=`aws ec2 describe-route-tables --filters Name=vpc-id,Values=${VPC_ID} --query RouteTables[].RouteTableId --output text`

SG_ID=`aws ec2 create-security-group --vpc-id ${VPC_ID} --group-name imagebuilder --description "imagebuilder security group" --query GroupId --output text`
aws ec2 create-tags --resources ${SG_ID} --tags Key=k8s.io/role/imagebuilder,Value=1

aws ec2 associate-route-table --route-table-id ${RT_ID} --subnet-id ${SUBNET_ID}

aws ec2 create-route --route-table-id ${RT_ID} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW_ID}

aws ec2 authorize-security-group-ingress  --group-id ${SG_ID} --protocol tcp --port 22 --cidr 0.0.0.0/0
```

Then:

```
go get sigs.k8s.io/image-builder/images/kube-deploy/imagebuilder
```

Build code: `make`

Run the image builder:
```
cd ${GOPATH}/src/sigs.k8s.io/image-builder/images/kube-deploy/imagebuilder
make
${GOPATH}/bin/imagebuilder --config aws.yaml --v=8
```

It will print the IDs of the image in each region, but it will also tag the
image with a Name as specified in the template) and this is the easier way to
retrieve the image.

## GCE

* Edit gce.yaml, at least to specify the Project and GCSDestination to use
* Create the GCS bucket in GCSDestination (if it does not exist) `gsutil mb
  gs://<bucketname>/`


Then:

```
go get sigs.k8s.io/image-builder/images/kube-deploy/imagebuilder
```

Run the image builder:
```
cd ${GOPATH}/src/sigs.k8s.io/image-builder/images/kube-deploy/imagebuilder`
make
${GOPATH}/bin/imagebuilder --config gce.yaml --v=8 --publish=false
```

Note that because GCE does not currently support publishing images, you must
pass `--publish=false`.  Also, images on GCE are global, so `replicate` does
not actually need to do anything.

Config file options
===================

ImageBuilder uses a YAML config file that specifies a number of key
configuration inputs. Some are specific to AWS or GCE.

| **Option**         | **Summary**                                                                                       |
|--------------------|---------------------------------------------------------------------------------------------------|
| `BootstrapVZBranch`| Git tag to pin `bootstrap-vz` to. Leave this at `image18` for now                                 |
| `BootstrapVZRepo`  | Path to `bootstrap-vz` git repo. Leave this at `https://github.com/justinsb/bootstrap-vz.git`     |
| `Cloud`            | Cloud provider. `aws` or `gce`                                                                    |
| `GCSDestination`   | Google Cloud Storage bucket to store the final cloud image in                                     |
| `ImageID`          | AWS machine image identifier (AMI) used for the _buildhost_  base OS where `bootstrap-vz` runs    |
| `InstanceProfile`  | Optional AWS IAM role to be attached to the buildhost EC2 instance where `bootstrap-vz` runs      |
| `InstanceType`     | Cloud compute instance type override, eg. `r4.large`                                              |
| `Project`          | Google Cloud project to associate with the generated cloud image                                  |
| `SSHPrivateKey`    | Path to SSH private key file in OpenSSH format. Default: `~/.ssh/id_rsa`                          |
| `SSHPublicKey`     | Path to SSH public key file in OpenSSH format. Default: `~/.ssh/id_rsa.pub`                       |
| `Tags`             | YAML map of cloud tags to be attached to the final cloud image                                    |
| `TemplatePath`     | Path to `bootstrap-vz` template file, eg. `templates/1.11-stretch.yml`                            |

Advanced options
================

Check out `--help`, but these options control which operations we perform,
and may be useful for debugging or publishing a lot of images:

* `--config=<configpath>` path to a config file, as described above. Lets you
  configure most options

* `--addtags=Foo=123,Bar=456,...` comma-separated list of additional cloud tags
  to apply. These will also be made available via Go templating in the
  `bootstrap-vz` configuration, specifically in the `Tags` map. See the next
  section for an example

* `--up=true/false`, `--down=true/false` control whether we try to create and
  terminate an instance to do the building

* `--publish=true/false` controls whether we make the image public

* `--replicate=true/false` controls whether we copy the image to all regions

Making use of tag data in templates
===================================

The below example is a real-world demo of how tag data can be used; the
assumption is that the `Branch` and `CIJob` are passed on the commandline with
the `--addtags` option, probably filled with data from a continuous-build
system.

```
{{- define "buildref" -}}
{{- if eq .Tags.Branch "master" -}}
{{- printf "master" -}}
{{- else -}}
{{- printf "%s" .Tags.CIJob -}}
{{- end -}}
{{- end -}}
{{ if eq .Cloud "aws" }}
name: k8s-1.9-debian-{system.release}-{system.architecture}-{provider.virtualization}-ebs-{%Y}-{%m}-{%d}-{{ template "buildref" . }}
{{ else }}
name: k8s-1.9-debian-{system.release}-{system.architecture}-{%Y}-{%m}-{%d}-{{- template "buildref" . }}
{{ end }}
```
