package converters

import (
	"path"

	"github.com/flanksource/commons/files"
	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg"
)

func DiskImageToVMDK(ctx *pkg.BuildContext, from api.Image, to api.Image) (api.Image, error) {

	disk := from.(api.DiskImage)
	vmdk := to.(api.VMDK)
	if vmdk.URL == "" {
		base = files.GetBaseName(disk.URL)
		dir := path.Dir(disk.URL)
		vmdk.URL = path.Join(dir, base+".vmdk")
	}

	if err := ctx.GetBinary("qemu-img")("convert -O vmdk -p %s %s", disk.URL, vmdk.URL); err != nil {
		return nil, err
	}
	return vmdk, nil
}
