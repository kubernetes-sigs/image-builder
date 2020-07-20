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
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"strings"

	"github.com/flanksource/commons/utils"
	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg"
)

type Docker struct {
}

func (d Docker) Kind() string {
	return "docker"
}

func (d Docker) CanConfigure(source api.Image) bool {
	return source.Kind() == "docker"
}

// Configures an image and returns the result or an error
func (d Docker) Configure(ctx pkg.BuildContext) (api.Image, error) {
	docker := ctx.GetBinary("docker")
	dockerfile := ""
	bash, err := ctx.Config.Konfigadm.ToBash()
	if err != nil {
		return nil, err
	}
	dockerImage := ctx.Input.(api.DockerImage)
	dockerfile += fmt.Sprintf("FROM %s:%s\n", dockerImage.Image, dockerImage.Tag)
	for _, cmd := range strings.Split(bash, "\n") {
		if strings.TrimSpace(cmd) == "" {
			continue
		}
		dockerfile += fmt.Sprintf("RUN %s\n", cmd)
	}
	tmp := fmt.Sprintf("Dockerfile.image-builder")
	defer os.Remove(tmp)

	out := dockerImage.Image + "-" + utils.ShortTimestamp()

	if err := ioutil.WriteFile(tmp, []byte(dockerfile), 0644); err != nil {
		return nil, err
	}
	if err := docker(fmt.Sprintf("build ./ -f %s -t %s", tmp, out)); err != nil {
		return nil, err
	}
	return api.DockerImage{
		Image: out,
		Tag:   "latest",
	}, nil
}

func (d Docker) AddFile(path string, contents io.Reader) error {
	return nil
}

func (d Docker) AddCommand(command ...string) error {
	return nil
}
