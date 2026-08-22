// Copyright 2026 The Kubernetes Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//go:build tools

// Keep the tracked modules in go.mod when Dependabot runs go mod tidy.
package tools

import (
	_ "github.com/containerd/containerd/v2/client"
	_ "github.com/containernetworking/plugins/pkg/ip"
	_ "github.com/opencontainers/runc/libcontainer"
	_ "k8s.io/client-go/kubernetes"
	_ "sigs.k8s.io/cri-tools/pkg/version"
)
