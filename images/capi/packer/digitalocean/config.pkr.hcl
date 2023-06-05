packer {
  required_plugins {
    digitalocean = {
      source =  "github.com/digitalocean/digitalocean"
      version = ">=1.1.1"
    }
  }
}
