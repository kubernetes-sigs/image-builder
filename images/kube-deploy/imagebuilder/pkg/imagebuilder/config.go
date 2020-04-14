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
	c.InstanceType = "c4.large"

	if region == "" {
		region = "us-east-1"
	}

	c.Region = region
	switch c.Region {
	case "cn-north-1":
		klog.Infof("Detected cn-north-1 region")
		// A slightly older image, but the newest one we have
		c.ImageID = "ami-da69a1b7"

	// Debian 10.3 images from https://wiki.debian.org/Cloud/AmazonEC2Image/Buster
	case "ap-east-1":
		c.ImageID = "ami-f9c58188"
	case "ap-northeast-1":
		c.ImageID = "ami-0fae5501ae428f9d7"
	case "ap-northeast-2":
		c.ImageID = "ami-0522874b039290246"
	case "ap-south-1":
		c.ImageID = "ami-03b4e18f70aca8973"
	case "ap-southeast-1":
		c.ImageID = "ami-0852293c17f5240b3"
	case "ap-southeast-2":
		c.ImageID = "ami-03ea2db714f1f6acf"
	case "ca-central-1":
		c.ImageID = "ami-094511e5020cdea18"
	case "eu-central-1":
		c.ImageID = "ami-0394acab8c5063f6f"
	case "eu-north-1":
		c.ImageID = "ami-0c82d9a7f5674320a"
	case "eu-west-1":
		c.ImageID = "ami-006d280940ad4a96c"
	case "eu-west-2":
		c.ImageID = "ami-08fe9ea08db6f1258"
	case "eu-west-3":
		c.ImageID = "ami-04563f5eab11f2b87"
	case "me-south-1":
		c.ImageID = "ami-0492a01b319d1f052"
	case "sa-east-1":
		c.ImageID = "ami-05e16feea94258a69"
	case "us-east-1":
		c.ImageID = "ami-04d70e069399af2e9"
	case "us-east-2":
		c.ImageID = "ami-04100f1cdba76b497"
	case "us-west-1":
		c.ImageID = "ami-014c78f266c5b7163"
	case "us-west-2":
		c.ImageID = "ami-023b7a69b9328e1f9"

	default:
		klog.Warningf("Building in unknown region %q - will require specifying an image, may not work correctly")
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
