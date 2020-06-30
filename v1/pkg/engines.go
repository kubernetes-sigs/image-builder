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

package pkg

import (
	"sigs.k8s.io/image-builder/api"
)

// Engines provide a mechanism to run an arbritraty set of commands
type Engine interface {
	Kind() string

	// CanConfigure returns true if the engine can configure the source
	CanConfigure(source api.Image) bool

	// Configures an image and returns the result or an error
	Configure(ctx BuildContext) (api.Image, error)
}
