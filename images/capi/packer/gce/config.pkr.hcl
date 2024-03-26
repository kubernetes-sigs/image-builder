packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.1, < 1.2"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}
