packer {
  required_plugins {
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
    goss = {
      version = ">= 3.2.14"
      source  = "github.com/YaleUniversity/goss"
    }
  }
}
