# Building Images for AWS

## Prerequisites for Amazon Web Services

- An AWS account
- The AWS CLI installed and configured

## Building Images

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building AMIs are managed by running:

```bash
make deps-ami
```

From the `images/capi` directory, run `make build-ami-<OS>`, where `<OS>` is
the desired operating system. The available choices are listed via `make help`.

To build all available OS's, uses the `-all` target. If you want to build them in parallel, use `make -j`. For example, `make -j build-ami-all`.

In the output of a successful `make` command is a list of created AMIs. To
format them you can copy the output and pipe it through this to get a desired
table:

```sh
echo 'us-fake-1: ami-123
us-fake-2: ami-234' | column -t | sed 's/^/| /g' | sed 's/: //g' | sed 's/ami/| ami/g' | sed 's/$/ |/g'
| us-fake-1 | ami-123 |
| us-fake-2 | ami-234 |
```

Note: If making the images public (the default), you must use one of the [Public CentOS images](https://wiki.centos.org/Cloud/AWS) as a base rather than a Marketplace image.

### Configuration

In addition to the configuration found in `images/capi/packer/config`, the `ami`
directory includes several JSON files that define the default configuration for
the different operating systems.

| File                 | Description                               |
|----------------------|-------------------------------------------|
| `amazon-2.json`      | The settings for the Amazon 2 Linux image |
| `flatcar.json`       | The settings for the Flatcar image        |
| `flatcar-arm64.json` | The settings for the Flatcar arm64 image  |
| `rhel-8.json`        | The settings for the RHEL 8 image         |
| `rockylinux.json`    | The settings for the Rocky Linux image    |
| `ubuntu-2204.json`   | The settings for the Ubuntu 22.04 image   |
| `ubuntu-2404.json`   | The settings for the Ubuntu 24.04 image   |
| `windows-2019.json`  | The settings for the Windows 2019 image   |


#### Common AWS options

This table lists several common options that a user may want to set via
`PACKER_VAR_FILES` to customize their build behavior.  This is not an exhaustive
list, and greater explanation can be found in the
[Packer documentation for the Amazon AMI builder](https://www.packer.io/docs/builders/amazon.html).

| Variable | Description                                                                                    | Default |
|----------|------------------------------------------------------------------------------------------------|---------|
| `ami_groups` | A list of groups that have access to launch the resulting AMI.                                 | `"all"` |
| `ami_regions` | A list of regions to copy the AMI to.                                                          | `"ap-south-1,eu-west-3,eu-west-2,eu-west-1,ap-northeast-2,ap-northeast-1,sa-east-1,ca-central-1,ap-southeast-1,ap-southeast-2,eu-central-1,us-east-1,us-east-2,us-west-1,us-west-2"` |
| `ami_users` | A list of users that have access to launch the resulting AMI.                                  | `"all"` |
| `aws_region` | The AWS region to build the AMI within.                                                        | `"us-east-1"` |
| `encrypted` | Indicates whether or not to encrypt the volume.                                                | `"false"` |
| `kms_key_id` | ID, alias or ARN of the KMS key to use for boot volume encryption.                             | `""` |
| `snapshot_groups` | A list of groups that have access to create volumes from the snapshot.                         | `"all"` |
| `snapshot_users` | A list of users that have access to create volumes from the snapshot.                          | `""` |
| `skip_create_ami` | If true, Packer will not create the AMI. Useful for setting to true during a build test stage. | `false` |

In the below examples, the parameters can be set via variable file and the use
of `PACKER_VAR_FILES`. See [Customization](../capi.md#customization) for
examples.

#### Examples

##### Building private AMIs

Set `ami_groups=""` and `snapshot_groups=""` parameters to
ensure you end up with a private AMI. Both parameters default to `"all"`.

##### Encrypted AMIs

Set `encrypted=true` for encrypted AMIs to allow for use with EC2 instances
backed by encrypted root volumes. You must also set `ami_groups=""` and
`snapshot_groups=""` for this to work.

##### Sharing private AMIs with other AWS accounts

Set `ami_users="012345789012,0123456789013"` to make your AMI visible to a
select number of other AWS accounts, and
`snapshot_users="012345789012,0123456789013"` to allow the EBS snapshot backing
the AMI to be copied.

If you are using encrypted root volumes in multiple accounts, you will want to
build one unencrypted AMI in a root account, setting `snapshot_users`, and then
use your own methods to copy the snapshot with encryption turned on into other
accounts.

##### Limiting AMI Regions

By default images are copied to many of the available AWS regions. See
`ami_regions` in [AWS options](#common-aws-options) for the default list. The
list of all available regions can be obtained running:

```sh
aws ec2 describe-regions --query "Regions[].{Name:RegionName}" --output text | paste -sd "," -
```

To limit the regions, provide the `ami_regions` variable as a comma-delimited list of AWS regions.

For example, to build all images in us-east-1 and copy only to us-west-2 set
`ami_regions="us-west-2"`.

## Required Permissions to Build the AWS AMIs

The [Packer documentation for the Amazon AMI builder](https://www.packer.io/docs/builders/amazon.html) supplies a suggested set of minimum permissions.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
      "Effect": "Allow",
      "Action" : [
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CopyImage",
        "ec2:CreateImage",
        "ec2:CreateKeypair",
        "ec2:CreateSecurityGroup",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteKeyPair",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteSnapshot",
        "ec2:DeleteVolume",
        "ec2:DeregisterImage",
        "ec2:DescribeImageAttribute",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DetachVolume",
        "ec2:GetPasswordData",
        "ec2:ModifyImageAttribute",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifySnapshotAttribute",
        "ec2:RegisterImage",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource" : "*"
  }]
}
```

## Testing Images

Connect remotely to an instance created from the image and run the Node Conformance tests using the following commands:

### Initialize a CNI

As root:

(copied from [containernetworking/cni](https://github.com/containernetworking/cni#how-do-i-use-cni))

```sh
mkdir -p /etc/cni/net.d
wget -q https://github.com/containernetworking/cni/releases/download/v0.7.0/cni-amd64-v0.7.0.tgz
tar -xzf cni-amd64-v0.7.0.tgz --directory /etc/cni/net.d
cat >/etc/cni/net.d/10-mynet.conf <<EOF
{
    "cniVersion": "0.2.0",
    "name": "mynet",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "10.22.0.0/16",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ]
    }
}
EOF
cat >/etc/cni/net.d/99-loopback.conf <<EOF
{
    "cniVersion": "0.2.0",
    "name": "lo",
    "type": "loopback"
}
EOF
```

### Run the e2e node conformance tests

As a non-root user:

```sh
wget https://dl.k8s.io/$(< /etc/kubernetes_community_ami_version)/kubernetes-test.tar.gz
tar -zxvf kubernetes-test.tar.gz kubernetes/platforms/linux/amd64
cd kubernetes/platforms/linux/amd64
sudo ./ginkgo --nodes=8 --flakeAttempts=2 --focus="\[Conformance\]" --skip="\[Flaky\]|\[Serial\]|\[sig-network\]|Container Lifecycle Hook" ./e2e_node.test -- --k8s-bin-dir=/usr/bin --container-runtime=remote --container-runtime-endpoint unix:///var/run/containerd/containerd.sock --container-runtime-process-name /usr/local/bin/containerd --container-runtime-pid-file= --kubelet-flags="--cgroups-per-qos=true --cgroup-root=/ --runtime-cgroups=/system.slice/containerd.service" --extra-log="{\"name\": \"containerd.log\", \"journalctl\": [\"-u\", \"containerd\"]}"
```
