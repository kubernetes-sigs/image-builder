package engines

import (
	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg"
)

type nullEngine struct{}

var NullEngine = nullEngine{}

func (n nullEngine) Kind() string {
	return "noop"
}

func (n nullEngine) Configure(ctx pkg.BuildContext) (api.Image, error) {
	return ctx.Input, nil
}

func (n nullEngine) CanConfigure(source api.Image) bool {
	return true
}
func (n nullEngine) String() string {
	return "nullEngine"
}
