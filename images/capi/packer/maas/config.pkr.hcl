packer {
  required_plugins {
    qemu = {
      source =  "github.com/hashicorp/qemu"
      version = "~> 1.1.0"
    }
  }
}
