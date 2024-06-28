packer {
  required_plugins {
    vultr = {
      source =  "github.com/vultr/vultr"
      version = ">= 2.5.0"
    }
  }
}
