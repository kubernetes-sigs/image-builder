module sigs.k8s.io/image-builder

go 1.12

require (
	github.com/fatih/structs v1.1.0
	github.com/flanksource/commons v1.3.5
	github.com/flanksource/konfigadm v0.7.3
	github.com/gopherjs/gopherjs v0.0.0-20181103185306-d547d1d9531e // indirect
	github.com/hashicorp/go-version v1.2.0 // indirect
	github.com/imdario/mergo v0.3.8
	github.com/miekg/dns v1.1.1 // indirect
	github.com/mitchellh/mapstructure v1.1.2
	github.com/onsi/ginkgo v1.7.0 // indirect
	github.com/palantir/stacktrace v0.0.0-20161112013806-78658fd2d177
	github.com/sirupsen/logrus v1.4.2
	github.com/spf13/cobra v0.0.5
	gopkg.in/flanksource/yaml.v3 v3.1.0
)

replace (
	// fix incorrect usage of root repo in downstream projects
	github.com/hashicorp/consul => github.com/hashicorp/consul/api v1.4.0
	github.com/hashicorp/vault => github.com/hashicorp/vault/api v1.0.4
)
