/*
Copyright 2019 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package packer

type Azure struct {
	Location       string `yaml:"location,omitempty"`
	VMSize         string `yaml:"vm_size,omitempty"`
	SubscriptionId string `yaml:"subscription_id,omitempty"`
	ClientId       string `yaml:"client_id,omitempty"`
	ClientSecret   string `yaml:"client_secret,omitempty"`
}

type AzureManagedImage struct {
	Name              string                        `yaml:"managed_image_name,omitempty"`
	ResourceGroupName string                        `yaml:"managed_image_resource_group_name,omitempty"`
	Destination       SharedImageGalleryDestination `yaml:"shared_image_gallery_destination,omitempty"`
}

type SharedImageGalleryDestination struct {
	ResourceGroup      string   `yaml:"resource_group,omitempty"`
	GalleryName        string   `yaml:"gallery_name,omitempty"`
	Name               string   `yaml:"image_name,omitempty"`
	Version            string   `yaml:"image_version,omitempty"`
	ReplicationRegions []string `yaml:"replication_regions,omitempty"`
}

type AzureImageStorage struct {
	ResourceGroup        string `yaml:"resource_group_name,omitempty"`
	CaptureContainerName string `yaml:"capture_container_name,omitempty"`
	CaptureNamePrefix    string `yaml:"capture_name_prefix,omitempty"`
	StorageAccount       string `yaml:"storage_account,omitempty"`
}

func NewAzure() Azure {
	return Azure{
		Location: "southcentralus",
		VMSize:   "Standard_B2ms",
	}
}
