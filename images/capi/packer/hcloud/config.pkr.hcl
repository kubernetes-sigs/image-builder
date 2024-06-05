packer {
  required_plugins {
    hcloud = {
      version = ">= 1.4.0"
      source  = "github.com/hetznercloud/hcloud"
    }
  }
}
