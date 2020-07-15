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

import (
	"fmt"
	"reflect"
	"strings"
)

type Variables struct {
	AnsibleSSHArgs     string `json:"existing_ansible_ssh_args,omitempty" structs:"existing_ansible_ssh_args,omitempty"`
	BootWait           string `json:"boot_wait,omitempty" structs:"boot_wait,omitempty"`
	BootKeyInterval    string `json:"boot_key_interval,omitempty" structs:"boot_key_interval,omitempty"`
	BuildName          string `json:"build_name,omitempty" structs:"build_name,omitempty"`
	BuildTimestamp     string `json:"build_timestamp,omitempty" structs:"build_timestamp,omitempty"`
	CPUCount           string `json:"cpu_count,omitempty" structs:"cpu_count,omitempty"`
	FloppyFiles        string `json:"floppy_files,omitempty" structs:"floppy_files,omitempty"`
	Headless           string `json:"headless,omitempty" structs:"headless,omitempty"`
	HTTPDir            string `json:"http_dir,omitempty" structs:"http_dir,omitempty"`
	Hostname           string `json:"hostname,omitempty" structs:"hostname,omitempty"`
	HttpDirectory      string `json:"http_directory,omitempty" structs:"http_directory,omitempty"`
	HTTPPortMax        int    `json:"http_port_max,omitempty" structs:"http_port_max,omitempty"`
	HTTPPortMin        int    `json:"http_port_min,omitempty" structs:"http_port_min,omitempty"`
	MemorySize         string `json:"memory_size,omitempty" structs:"memory_size,omitempty"`
	OutputDir          string `json:"output_dir,omitempty" structs:"output_dir,omitempty"`
	SkipCompaction     bool   `json:"skip_compaction,omitempty" structs:"skip_compaction,omitempty"`
	SSHHostPortMax     int    `json:"ssh_host_port_max,omitempty" structs:"ssh_host_port_max,omitempty"`
	SSHHostPortMin     int    `json:"ssh_host_port_min,omitempty" structs:"ssh_host_port_min,omitempty"`
	SSHTimeout         string `json:"ssh_timeout,omitempty" structs:"ssh_timeout,omitempty"`
	Password           string `json:"ssh_password,omitempty" structs:"ssh_password,omitempty"`
	Username           string `json:"ssh_username,omitempty" structs:"ssh_username,omitempty"`
	VMName             string `json:"vm_name,omitempty" structs:"vm_name,omitempty"`
	VNCBindAddress     string `json:"vnc_bind_address,omitempty" structs:"vnc_bind_address,omitempty"`
	VNCDisablePassword string `json:"vnc_disable_password,omitempty" structs:"vnc_disable_password,omitempty"`
	VNCPortMax         string `json:"vnc_port_max,omitempty" structs:"vnc_port_max,omitempty"`
	VNCPortMin         string `json:"vnc_port_min,omitempty" structs:"vnc_port_min,omitempty"`
}

func (v Variables) AsVarReferences() map[string]interface{} {
	refs := make(map[string]interface{})
	typeOf := reflect.TypeOf(v)
	valueOf := reflect.ValueOf(v)

	for i := 0; i < typeOf.NumField(); i++ {
		field := typeOf.Field(i)
		val := valueOf.Field(i)
		name := strings.Split(field.Tag.Get("json"), ",")[0]

		if val.Kind() == reflect.Ptr {
			val = val.Elem()
		}

		switch val.Interface() {
		case "":
			continue
		case 0:
			continue
		}

		ref := fmt.Sprintf("{{ user `%s` }}", name)

		if val.Kind() == reflect.Slice {
			refs[name] = []string{ref}
		} else {
			refs[name] = ref
		}
	}
	return refs
}

func NewVariables() Variables {
	return Variables{
		AnsibleSSHArgs:     "{{env `ANSIBLE_SSH_ARGS`}}",
		BootWait:           "10s",
		BuildTimestamp:     "{{timestamp}}",
		CPUCount:           "1",
		Headless:           "true",
		MemorySize:         "1024",
		OutputDir:          "./output/{{user `build_name`}}-kube-{{user `kubernetes_semver`}}",
		SkipCompaction:     false,
		VMName:             "",
		HttpDirectory:      "http",
		VNCBindAddress:     "127.0.0.1",
		VNCDisablePassword: "false",
		VNCPortMax:         "6000",
		VNCPortMin:         "5900",
		Username:           "builder",
		SSHTimeout:         "10m",
		Hostname:           "{{user `build_name`}}-kube-{{user `kubernetes_semver`}}",
		Password:           "builder",
	}
}
