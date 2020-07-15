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

package engines

import (
	"io"

	"github.com/flanksource/commons/logger"
	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg"
	"sigs.k8s.io/image-builder/pkg/engines/packer"
)

type Packer struct {
}

func (p Packer) Kind() string {
	return "packer"
}

func (p Packer) CanConfigure(source api.Image) bool {
	return source.Kind() == "packer"
}

// Configures an image and returns the result or
func (p Packer) Configure(ctx pkg.BuildContext) (api.Image, error) {
	config, err := packer.NewPacker(ctx)
	if err != nil {
		return nil, err
	}

	manifest, err := config.Build()
	if err != nil {
		return nil, err
	}

	logger.Prettyf("Finished build", manifest)
	return manifest.GetImage()
}

func (p Packer) AddFile(path string, contents io.Reader) error {
	return nil
}

func (p Packer) AddAnsiblePlaybook(path string) error {
	return nil
}

func (p Packer) AddCommand(command ...string) error {
	return nil
}
