packer {
  required_plugins {
    vultr = {
      source =  "github.com/hashicorp/qemu"
      version = "~> 1.1.0"
    }
  }
}
