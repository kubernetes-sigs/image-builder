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
	konfigadm "github.com/flanksource/konfigadm/pkg/types"
)

type PackerEngine struct {
	Version  string                            `yaml:"version"`
	Builders map[string]map[string]interface{} `yaml:"builders,omitempty"`
}

// packer build options are too many sync
// TODO: import the packer config objects directly and workaround the mapstructure issues
type PackerBuilderOptions map[string]interface{}

type QemuOptions map[string]interface{}

type KubernetesConfiguration struct {
	Konfigadm konfigadm.Config `yaml:"konfigadm,omitempty`

	// The OS distribution configuration
	DistroName string `yaml:"distroName"`

	Input map[string]interface{} `yaml:"input"`

	Output []map[string]interface{} `yaml:"output"`

	Engine map[string]interface{} `yaml:"engine,omitempty"`

	Packer PackerEngine `yaml:"packer,omitempty"`
	Qemu   QemuOptions  `yaml:"qemu,omitempty"`

	// The version of kubernetes to install
	Version string `yaml:"version,omitempty" json:"version,omitempty"`
}

func (k KubernetesConfiguration) GetSemVer() string {
	return k.Version
}

func (k KubernetesConfiguration) GetSeries() string {
	return k.Version
}
