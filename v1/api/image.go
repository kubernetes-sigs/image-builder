/*
 Copyright 2020 The Kubernetes Authors

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

package api

import (
	"fmt"

	"github.com/imdario/mergo"
	"github.com/mitchellh/mapstructure"
)

type Image interface {
	Kind() string
	String() string
	GetPackerOptions() (*PackerBuilderOptions, error)
	GetQemuOptions() (*QemuOptions, error)
}

const (
	AMIKind         = "ami"
	AzureKind       = "azure"
	DiskImageKind   = "img"
	DockerImageKind = "docker"
	GCEImageKind    = "gce"
	OVAKind         = "ova"
	ISOKind         = "iso"
	VMKind          = "vm"
	VMDKKind        = "vmdk"
)

type AMI struct {
	Tags    map[string]string `yaml:"tags,omitempty" structs:"tags,omitempty" json:"tags,omitempty"`
	Name    string            `yaml:"name,omitempty" structs:"name,omitempty" json:"name,omitempty"`
	ID      string            `yaml:"id,omitempty" structs:"owners,omitempty" json:"id,omitempty"`
	Region  string            `yaml:"region,omitempty" structs:"owners,omitempty" json:"region,omitempty"`
	Account string            `yaml:"account,omitempty" structs:"owners,omitempty" json:"account,omitempty"`
	Owners  []string          `yaml:"owners,omitempty" structs:"owners,omitempty" json:"owners,omitempty"`
}

func (i AMI) Kind() string {
	return AMIKind
}

func (i AMI) String() string {
	return i.ID
}
func (i AMI) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i AMI) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

type AzureImage struct {
	ID             string `yaml:"id,omitempty" json:"id,omitempty"`
	ImagePublisher string `yaml:"image_publisher,omitempty" json:"image_publisher,omitempty"`
	ImageOffer     string `yaml:"image_offer,omitempty" json:"image_offer,omitempty"`
	ImageSKU       string `yaml:"image_sku,omitempty" json:"image_sku,omitempty"`
}

func (i AzureImage) Kind() string {
	return AzureKind
}

func (i AzureImage) String() string {
	return AzureKind
}

func (i AzureImage) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i AzureImage) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

type DiskImage struct {
	URL            string `yaml:"url,omitempty" structs:"iso_url,omitempty"`
	Checksum       string `yaml:"checksum,omitempty" structs:"iso_checksum,omitempty"`
	ChecksumType   string `yaml:"checksum_type,omitempty" structs:"iso_checksum_type,omitempty"`
	CaptureLogs    string `yaml:"capture_logs,omitempty"`
	ResizeGB       int    `yaml:"resize_gb,omitempty"`
	Inline         bool   `yaml:"inline,omitempty"`
	OutputDir      string `yaml:"output_dir,omitempty"`
	OutputFilename string `yaml:"output_filename,omitempty"`
}

func (i DiskImage) Kind() string {
	return DiskImageKind
}

func (i DiskImage) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i DiskImage) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

func (i DiskImage) String() string {
	return i.URL
}

type DockerImage struct {
	Image    string `yaml:"image,omitempty" `
	Tag      string `yaml:"tag,omitempty" `
	Checksum string `yaml:"checksum,omitempty" `
}

func (i DockerImage) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i DockerImage) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

func (i DockerImage) String() string {
	return fmt.Sprintf("%s:%s", i.Image, i.Tag)
}

func (i DockerImage) Kind() string {
	return DockerImageKind
}

type GCEImage struct {
	MachineType       string `yaml:"machine_type,omitempty"`
	SourceImageFamily string `yaml:"source_image_family,omitempty"`
	ImageName         string `yaml:"image_name,omitempty"`
	ImageFamily       string `yaml:"image_family,omitempty"`
	Zone              string `yaml:"zone,omitempty"`
	Image
}

func (i GCEImage) Kind() string {
	return GCEImageKind
}

func (i GCEImage) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i GCEImage) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

type ISO struct {
	URL             string `yaml:"url,omitempty" structs:"iso_url,omitempty"`
	Checksum        string `yaml:"checksum,omitempty" structs:"iso_checksum,omitempty"`
	ChecksumType    string `yaml:"checksum_type,omitempty" structs:"iso_checksum_type,omitempty"`
	ShutdownCommand string `yaml:"shutdown_command,omitempty"`
	BootCommand     string `yaml:"boot_commmand,omitempty"`
}

func (i ISO) Kind() string {
	return ISOKind
}

func (i ISO) String() string {
	return i.URL
}

func (i ISO) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i ISO) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

type OVA struct {
	URL        string
	Properties map[string]string `yaml:"properties,omitempty"`
	EULA       string            `yaml:"eula,omitempty"`
}

func (i OVA) Kind() string {
	return OVAKind
}

func (i OVA) String() string {
	return i.URL
}

func (i OVA) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i OVA) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

type VM struct {
	Tags    map[string]string `yaml:"tags,omitempty" structs:"tags,omitempty" json:"tags,omitempty"`
	Name    string            `yaml:"name,omitempty" structs:"name,omitempty" json:"name,omitempty"`
	ID      string            `yaml:"id,omitempty" structs:"owners,omitempty" json:"id,omitempty"`
	Network string            `yaml:"network,omitempty"`
}

func (i VM) Kind() string {
	return VMKind
}

func (i VM) String() string {
	return i.Name
}

func (i VM) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i VM) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

type VMDK struct {
	URL string `yaml:"url,omitempty"`
}

func (i VMDK) Kind() string {
	return VMDKKind
}

func (i VMDK) String() string {
	return i.URL
}

func (i VMDK) GetPackerOptions() (*PackerBuilderOptions, error) {
	return nil, nil
}

func (i VMDK) GetQemuOptions() (*QemuOptions, error) {
	return nil, nil
}

func GetImage(opts map[string]interface{}) (Image, error) {
	// FIXME mapstructure requires a concrete type, when passed a value referenced by
	// an interface it does not decode anything.
	switch opts["kind"].(string) {
	case "qemu", "img", "qcow2":
		driver := DiskImage{}
		if err := decode(opts, &driver); err != nil {
			return nil, err
		}
		return driver, nil
	case "ova":
		driver := OVA{}
		if err := decode(opts, &driver); err != nil {
			return nil, err
		}
		return driver, nil
	case "ami":
		driver := AMI{}
		if err := decode(opts, &driver); err != nil {
			return nil, err
		}
		return driver, nil
	case "vpshere":
		driver := VM{}
		if err := decode(opts, &driver); err != nil {
			return nil, err
		}
		return driver, nil
	case "azure":
		driver := AzureImage{}
		if err := decode(opts, &driver); err != nil {
			return nil, err
		}
		return driver, nil
	case "gce":
		driver := GCEImage{}
		if err := decode(opts, &driver); err != nil {
			return nil, err
		}
		return driver, nil
	case "vmdk":
		driver := VMDK{}
		if err := decode(opts, &driver); err != nil {
			return nil, err
		}
		return driver, nil
	}
	return nil, fmt.Errorf("unknown driver kind %s", opts["kind"])
}

func decode(opts map[string]interface{}, into interface{}) error {
	metadata := &mapstructure.Metadata{}
	decoder, err := mapstructure.NewDecoder(&mapstructure.DecoderConfig{
		TagName:          "yaml",
		Result:           into,
		Metadata:         metadata,
		WeaklyTypedInput: true,
	})
	if err != nil {
		return err
	}
	return decoder.Decode(opts)
}

func Merge(input Image, from Image) (Image, error) {
	if from == nil {
		return input, nil
	}
	switch from.(type) {
	case AMI:
		amiImage := input.(AMI)
		if err := mergo.Merge(&amiImage, from.(AMI)); err != nil {
			return nil, err
		}
		return amiImage, nil
	case ISO:
		isoImage := input.(ISO)
		if err := mergo.Merge(&isoImage, from.(ISO)); err != nil {
			return nil, err
		}
		return isoImage, nil
	case DockerImage:
		dockerImage := input.(DockerImage)
		if err := mergo.Merge(&dockerImage, from.(DockerImage)); err != nil {
			return nil, err
		}
		return dockerImage, nil
	case DiskImage:
		diskImage := input.(DiskImage)
		if err := mergo.Merge(&diskImage, from.(DiskImage)); err != nil {
			return nil, err
		}
		return diskImage, nil
	case GCEImage:
		gceImage := input.(GCEImage)
		if err := mergo.Merge(&gceImage, from.(GCEImage)); err != nil {
			return nil, err
		}
		return gceImage, nil
	case AzureImage:
		azureImage := input.(AzureImage)
		if err := mergo.Merge(&azureImage, from.(AzureImage)); err != nil {
			return nil, err
		}
		return azureImage, nil
	case OVA:
		ovaImage := input.(OVA)
		if err := mergo.Merge(&ovaImage, from.(OVA)); err != nil {
			return nil, err
		}
		return ovaImage, nil
	case VMDK:
		vmdk := input.(VMDK)
		if err := mergo.Merge(&vmdk, from.(VMDK)); err != nil {
			return nil, err
		}
		return vmdk, nil
	}
	return nil, fmt.Errorf("unknown image type: %v -> %v", input, from)
}
