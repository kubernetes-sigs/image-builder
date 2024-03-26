packer {
  required_version = ">= 1.7.0"
  required_plugins {
    vmware = {
      version = ">= 1.0.8, < 1.1"
      source  = "github.com/hashicorp/vmware"
    }
    vsphere = {
      version = ">= 1.2.1, < 1.3"
      source  = "github.com/hashicorp/vsphere"
    }
  }
}
