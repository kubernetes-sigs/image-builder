packer {
  required_plugins {
    azure = {
      version = ">= 2.1.8"
      source  = "github.com/hashicorp/azure"
    }
  }
}
