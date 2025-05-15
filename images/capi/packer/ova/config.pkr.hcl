packer {
  required_version = ">= 1.7.0"
  required_plugins {
    vsphere = {
      version = ">= 1.4.2"
      source  = "github.com/hashicorp/vsphere"
    }
  }
}
