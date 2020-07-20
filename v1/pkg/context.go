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

package pkg

import (
	"fmt"

	"github.com/flanksource/commons/deps"
	"github.com/flanksource/commons/logger"
	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg/distros"
)

type BuildContext struct {
	logger.Logger
	Engine    Engine
	Config    api.KubernetesConfiguration
	Input     api.Image
	Output    []api.Image
	Distro    distros.Distribution
	Variables map[string]interface{}
	Defaults  map[string]map[string]interface{}
	DryRun    bool
}

func (ctx BuildContext) String() string {
	return fmt.Sprintf("input=%s  output=%s engine=%s distro=%s", ctx.Input, ctx.Output, ctx.Engine, ctx.Distro)
}

func (ctx BuildContext) GetBinary(name string) deps.BinaryFunc {
	if ctx.DryRun {
		return func(msg string, args ...interface{}) error {
			logger.Infof(msg, args)
			return nil
		}
	}
	return deps.Binary(name, "", "")
}
