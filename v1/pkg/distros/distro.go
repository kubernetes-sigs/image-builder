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

package distros

import (
	"fmt"
	"io/ioutil"

	"gopkg.in/flanksource/yaml.v3"
	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg/resources"
)

var specs = []string{"ubuntu.yml", "debian.yml", "redhat.yml", "amazonLinux.yml"}
var Distributions = make(map[string]Distribution)

type Distribution interface {
	api.EngineHooks
	GetDistribution() *api.Distribution
}

func GetDistroByName(name string) (Distribution, error) {
	if v, ok := Distributions[name]; ok {
		return v, nil
	}
	return nil, fmt.Errorf("Unknown distro name: %s", name)
}

func GetDistro(distro api.Distribution) (Distribution, error) {
	switch distro.OS {
	case "ubuntu":
		return Ubuntu{Distribution: distro}, nil
	case "debian":
		return Debian{Distribution: distro}, nil
	case "centos", "amazonLinux", "redhat":
		return Centos{Distribution: distro}, nil
	}
	return Ubuntu{Distribution: distro}, nil
}

func GetDistributions() (map[string]Distribution, error) {
	if len(Distributions) > 0 {
		return Distributions, nil
	}
	fs := resources.FS(false)
	dir, err := fs.Open("/distros")
	if err != nil {
		return nil, fmt.Errorf("/ does not exist, did you run mack pack?: %v", err)
	}
	files, err := dir.Readdir(-1)
	if err != nil {
		return nil, err
	}

	for _, info := range files {
		file, _ := fs.Open("/distros/" + info.Name())
		if err != nil {
			return nil, err
		}
		data, err := ioutil.ReadAll(file)
		if err != nil {
			return nil, err
		}
		var values map[string]api.Distribution
		if err := yaml.Unmarshal(data, &values); err != nil {
			return nil, fmt.Errorf("error unmarshalling %s: %v", info.Name(), err)
		}
		for k, v := range values {
			distro, err := GetDistro(v)
			if err != nil {
				return nil, err
			}
			Distributions[k] = distro
		}
	}
	return Distributions, nil
}
