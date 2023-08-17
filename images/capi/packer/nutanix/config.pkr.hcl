packer {
  required_plugins {
    nutanix = {
      version = ">= 0.7.0, < 0.8.0"
      source = "github.com/nutanix-cloud-native/nutanix"
    }
  }
}
