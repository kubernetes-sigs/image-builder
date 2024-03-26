packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.9, < 1.1"
      source  = "github.com/hashicorp/qemu"
    }
  }
}
