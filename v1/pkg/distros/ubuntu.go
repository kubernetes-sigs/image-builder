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
	"bytes"

	"github.com/flanksource/commons/text"

	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg/resources"
)

type Ubuntu struct {
	api.Distribution
}

func (u Ubuntu) Before(engine api.Executor) error {

	engine.AddCommand(
		"while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
		"sudo apt-get -qq update && sudo DEBIAN_FRONTEND=noninteractive apt-get -qqy install python python-pip")

	preseed := resources.FSMustString(false, "preseed.cfg")
	preseed, err := text.Template(preseed, engine)
	if err != nil {
		return err
	}
	return engine.AddFile("http/preseed.cfg", bytes.NewBufferString(preseed))
}

func (u Ubuntu) After(engine api.Executor) error {
	return nil
}

func (u Ubuntu) GetDistribution() *api.Distribution {
	return &u.Distribution
}
