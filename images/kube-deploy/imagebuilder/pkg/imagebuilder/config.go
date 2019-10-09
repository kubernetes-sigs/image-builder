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

	// Debian 9.10 images from https://wiki.debian.org/Cloud/AmazonEC2Image/Stretch
	case "ap-northeast-1":
		c.ImageID = "ami-0c6a2f2f2f4a70aea"
	case "ap-northeast-2":
		c.ImageID = "ami-0cbc427c7cf153743"
	case "ap-south-1":
		c.ImageID = "ami-09cfadd383378b3c6"
	case "ap-southeast-1":
		c.ImageID = "ami-0c7b4220e70a330dc"
	case "ap-southeast-2":
		c.ImageID = "ami-04f3947810b6f3510"
	case "ca-central-1":
		c.ImageID = "ami-053436ba7a956a4dc"
	case "eu-central-1":
		c.ImageID = "ami-08b86eba424e765ec"
	case "eu-north-1":
		c.ImageID = "ami-05b74a5b2e19a2a97"
	case "eu-west-1":
		c.ImageID = "ami-0211a849817dcceca"
	case "eu-west-2":
		c.ImageID = "ami-0536206ce3bd2c36f"
	case "eu-west-3":
		c.ImageID = "ami-045fa58af83eb0ff4"
	case "sa-east-1":
		c.ImageID = "ami-056f0447a169d5f76"
	case "us-east-1":
		c.ImageID = "ami-0ed2d2283aa1466df"
	case "us-east-2":
		c.ImageID = "ami-07a0560634acb945f"
	case "us-west-1":
		c.ImageID = "ami-0ff3a5bef845ec04f"
	case "us-west-2":
		c.ImageID = "ami-0fdf2e9fd534f1b2f"

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
