packer {
  required_plugins {
    nutanix = {
      version = ">= 0.3.1"
      source = "github.com/nutanix-cloud-native/nutanix"
    }
  }
}
