module sigs.k8s.io/image-builder

go 1.12

require (
	github.com/containerd/containerd v1.3.4
	github.com/fatih/structs v1.1.0
	github.com/flanksource/commons v1.3.5
	github.com/flanksource/konfigadm v0.7.3
	github.com/hashicorp/consul/api v1.4.0
	github.com/hashicorp/packer v1.4.4
	github.com/hashicorp/vault/api v1.0.4
	github.com/imdario/mergo v0.3.8
	github.com/mitchellh/colorstring v0.0.0-20190213212951-d06e56a500db
	github.com/mitchellh/mapstructure v1.1.2
	github.com/palantir/stacktrace v0.0.0-20161112013806-78658fd2d177
	github.com/pkg/errors v0.9.1
	github.com/sirupsen/logrus v1.4.2
	github.com/spf13/cobra v0.0.5
	gopkg.in/flanksource/yaml.v3 v3.1.0
)

replace (
	// fix incorrect usage of root repo in downstream projects
	github.com/hashicorp/consul => github.com/hashicorp/consul/api v1.4.0
	github.com/hashicorp/vault => github.com/hashicorp/vault/api v1.0.4
)
