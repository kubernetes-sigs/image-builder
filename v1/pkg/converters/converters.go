package converters

import (
	"fmt"

	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg"
)

type Converter func(ctx *pkg.BuildContext, from api.Image, to api.Image) (api.Image, error)

var Converters = map[string]Converter{
	"vmdk->ova":  VmdkToOVA,
	"ova->vm":    OVAToVM,
	"qcow->vmdk": DiskImageToVMDK,
	"disk->vmdk": DiskImageToVMDK,
	"img->vmdk":  DiskImageToVMDK,
}

func Convert(ctx *pkg.BuildContext, from api.Image, to api.Image) (api.Image, error) {
	name := fmt.Sprintf("%s->%s", from.Kind(), to.Kind())

	converter, ok := Converters[name]
	if !ok {
		return nil, fmt.Errorf("no converter found for %s", name)
	}
	return converter(ctx, from, to)
}
