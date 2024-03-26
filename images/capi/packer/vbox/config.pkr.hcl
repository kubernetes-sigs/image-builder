packer {
  required_plugins {
    vagrant = {
      version = ">= 1.0.3, < 1.1"
      source  = "github.com/hashicorp/vagrant"
    }
    virtualbox = {
      version = ">= 1.0.5, < 1.1"
      source  = "github.com/hashicorp/virtualbox"
    }
  }
}
