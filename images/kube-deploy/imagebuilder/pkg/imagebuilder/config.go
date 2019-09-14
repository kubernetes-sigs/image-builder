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
		"sudo pip install --upgrade requests termcolor jsonschema fysom docopt pyyaml boto boto3",
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
	c.InstanceType = "m3.medium"

	if region == "" {
		region = "us-east-1"
	}

	c.Region = region
	switch c.Region {
	case "cn-north-1":
		klog.Infof("Detected cn-north-1 region")
		// A slightly older image, but the newest one we have
		c.ImageID = "ami-da69a1b7"

	// Debian 9.5 images from https://wiki.debian.org/Cloud/AmazonEC2Image/Stretch
	case "ap-northeast-1":
		c.ImageID = "ami-048813c43a892bf4a"
	case "ap-northeast-2":
		c.ImageID = "ami-0b61dc7b9ac9452c7"
	case "ap-south-1":
		c.ImageID = "ami-02f59cc6982469cd2"
	case "ap-southeast-1":
		c.ImageID = "ami-0a9a79bb079115e9b"
	case "ap-southeast-2":
		c.ImageID = "ami-0abf02e9015527575"
	case "ca-central-1":
		c.ImageID = "ami-0e825d093523065f9"
	case "eu-central-1":
		c.ImageID = "ami-0681ed9bb7a58a33d"
	case "eu-west-1":
		c.ImageID = "ami-0483f1cc1c483803f"
	case "eu-west-2":
		c.ImageID = "ami-0d9ba70fd9e495233"
	case "eu-west-3":
		c.ImageID = "ami-0b59b5cf392c3c2b3"
	case "sa-east-1":
		c.ImageID = "ami-0bd8e4655e2beef08"
	case "us-east-1":
		c.ImageID = "ami-03006931f694ea7eb"
	case "us-east-2":
		c.ImageID = "ami-06dfb9abeb4a6afc6"
	case "us-west-1":
		c.ImageID = "ami-0f0674cb683fcc1f7"
	case "us-west-2":
		c.ImageID = "ami-0a1fbca0e5b419fd1"

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
