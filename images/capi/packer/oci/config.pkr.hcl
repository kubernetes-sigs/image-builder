packer {
  required_plugins {
    vultr = {
      source =  "github.com/hashicorp/oracle"
      version = "~> 1.1.0"
    }
  }
}
