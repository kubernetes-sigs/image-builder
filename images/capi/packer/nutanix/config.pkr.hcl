packer {
  required_plugins {
    nutanix = {
      version = ">= 0.8.1"
      source = "github.com/nutanix-cloud-native/nutanix"
    }
  }
}
