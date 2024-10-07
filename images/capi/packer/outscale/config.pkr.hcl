packer {
  required_plugins {
    vultr = {
      source =  "github.com/outscale/outscale"
      version = "~> 1.2.0"
    }
  }
}
