package imagebuilder

import (
	"strings"

	"k8s.io/klog"
)

type Config struct {
	Cloud         string
	TemplatePath  string
	SetupCommands [][]string

	BootstrapVZRepo   string
	BootstrapVZBranch string

	SSHUsername   string
	SSHPublicKey  string
	SSHPrivateKey string

	InstanceProfile string

	// Tags to add to the image
	Tags map[string]string
}

func (c *Config) InitDefaults() {
	c.BootstrapVZRepo = "https://github.com/andsens/bootstrap-vz.git"
	c.BootstrapVZBranch = "master"

	c.SSHUsername = "admin"
	c.SSHPublicKey = "~/.ssh/id_rsa.pub"
	c.SSHPrivateKey = "~/.ssh/id_rsa"

	c.InstanceProfile = ""

	setupCommands := []string{
		"sudo apt-get update",
		"sudo apt-get install --yes git python debootstrap python-pip kpartx parted",
		"sudo pip install --upgrade requests termcolor jsonschema fysom docopt pyyaml boto boto3 pyrsistent==0.16.0",
	}
	for _, cmd := range setupCommands {
		c.SetupCommands = append(c.SetupCommands, strings.Split(cmd, " "))
	}
}

type AWSConfig struct {
	Config

	Region          string
	ImageID         string
	InstanceType    string
	SSHKeyName      string
	SubnetID        string
	SecurityGroupID string
	Tags            map[string]string
}

func (c *AWSConfig) InitDefaults(region string) {
	c.Config.InitDefaults()
	c.InstanceType = "m4.large"

	if region == "" {
		region = "us-east-1"
	}

	c.Region = region
	switch c.Region {
	case "cn-north-1":
		klog.Infof("Detected cn-north-1 region")
		// A slightly older image, but the newest one we have
		c.ImageID = "ami-da69a1b7"

	// Debian 9.10 images from https://wiki.debian.org/Cloud/AmazonEC2Image/Stretch
	case "ap-east-1":
		c.ImageID = "ami-0a81e23ced9c32d26"
	case "ap-northeast-1":
		c.ImageID = "ami-0aad015f7b135e198"
	case "ap-northeast-2":
		c.ImageID = "ami-00a96e50f990be54c"
	case "ap-south-1":
		c.ImageID = "ami-0c7bd0941d9b93c88"
	case "ap-southeast-1":
		c.ImageID = "ami-0cca8bafd3ad1ad08"
	case "ap-southeast-2":
		c.ImageID = "ami-0c6d33437a8337f6e"
	case "ca-central-1":
		c.ImageID = "ami-001c474f9452c7d93"
	case "eu-central-1":
		c.ImageID = "ami-04dd896c9036d974b"
	case "eu-north-1":
		c.ImageID = "ami-04cc93d303a4dd18c"
	case "eu-west-1":
		c.ImageID = "ami-08d95e3db80c57a5e"
	case "eu-west-2":
		c.ImageID = "ami-04129aa76aebf3aa2"
	case "eu-west-3":
		c.ImageID = "ami-024a4edbad921fd5c"
	case "me-south-1":
		c.ImageID = "ami-0e8670e0374463e7b"
	case "sa-east-1":
		c.ImageID = "ami-082e93a75a7f2ba1d"
	case "us-east-1":
		c.ImageID = "ami-02c3fa55e499f1fb3"
	case "us-east-2":
		c.ImageID = "ami-06858f33bbe384bbb"
	case "us-west-1":
		c.ImageID = "ami-0dd6bad099b8b3889"
	case "us-west-2":
		c.ImageID = "ami-0964442b6f325859a"

	default:
		klog.Warningf("Building in unknown region %q - will require specifying an image, may not work correctly")
	}

	// Not all regions support m3.medium
	switch c.Region {
	case "us-east-2":
		c.InstanceType = "m4.large"
	}
}

type GCEConfig struct {
	Config

	// To create an image on GCE, we have to upload it to a bucket first
	GCSDestination string

	Project     string
	Zone        string
	MachineName string

	MachineType string
	Image       string
	Tags        map[string]string
}

func (c *GCEConfig) InitDefaults() {
	c.Config.InitDefaults()
	c.MachineName = "k8s-imagebuilder"
	c.Zone = "us-central1-f"
	c.MachineType = "n1-standard-2"
	c.Image = "https://www.googleapis.com/compute/v1/projects/debian-cloud/global/images/debian-8-jessie-v20160329"
}
