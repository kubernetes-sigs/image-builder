packer {
  required_plugins {
    azure = {
      version = ">= 1.4.3"
      source  = "github.com/hashicorp/azure"
    }
  }
}
