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
	"os"
	"path"
	"strings"

	"github.com/flanksource/commons/console"
	"github.com/flanksource/commons/files"
	"github.com/flanksource/commons/logger"
	"github.com/flanksource/commons/utils"
	cloudinit "github.com/flanksource/konfigadm/pkg/cloud-init"
	konfigadm "github.com/flanksource/konfigadm/pkg/types"

	"sigs.k8s.io/image-builder/api"
	"sigs.k8s.io/image-builder/pkg"
)

type Qemu struct {
}

func (q Qemu) String() string {
	return "qemu"
}

func (q Qemu) Kind() string {
	return "qemu"
}

func (q Qemu) CanConfigure(source api.Image) bool {
	return source.Kind() == "qemu"
}

// Configures an image and returns the result or
func (q Qemu) Configure(ctx pkg.BuildContext) (api.Image, error) {
	input := ctx.Input.(api.DiskImage)
	if input.URL != "" && input.Inline && !strings.HasPrefix(input.URL, "http") {
		return input, nil
	}

	var scratch Scratch
	if input.CaptureLogs != "" {
		logger.Infof("Using scratch directory / disk")
		scratch = NewScratch()
	}

	image, err := q.clone(ctx, input.URL)
	if err != nil {
		return nil, err
	}
	iso, err := createIso(&ctx.Config.Konfigadm)
	if err != nil {
		return nil, fmt.Errorf("failed to build ISO %v", err)
	}
	if iso == "" {
		return nil, fmt.Errorf("empty ISO created")
	}
	cmdLine := fmt.Sprintf(`\
	-nodefaults \
	-display none \
	-machine accel=kvm:hvf \
	-cpu host -smp cpus=2 \
	-m 1024 \
	-hda %s \
	-cdrom %s \
	-device virtio-serial-pci \
	-serial stdio \
	-net nic -net user,hostfwd=tcp:127.0.0.1:2022-:22`, image, iso)
	if input.CaptureLogs != "" {
		cmdLine += fmt.Sprintf(" -hdb %s", scratch.GetImg())
	}

	logger.Infof("Executing %s", console.Greenf(cmdLine))
	if err := ctx.GetBinary("qemu-system")(cmdLine); err != nil {
		return nil, fmt.Errorf("failed to run: %s, %s", cmdLine, err)
	}
	if input.CaptureLogs != "" {
		logger.Infof("Coping captured logs to %s", input.CaptureLogs)
		scratch.UnwrapToDir(input.CaptureLogs)
	}
	return api.DiskImage{
		URL: image,
	}, nil
}

func (q Qemu) copyImage(ctx pkg.BuildContext, image string) (string, error) {

	from := ctx.Input.(api.DiskImage)
	cachedImage := image
	if from.OutputFilename != "" {
		image = files.GetBaseName(from.OutputFilename) + path.Ext(image)
	} else {
		image = files.GetBaseName(image) + "-" + utils.ShortTimestamp() + path.Ext(image)
	}

	if from.OutputDir != "" {
		image = path.Join(from.OutputDir, image)
	}

	logger.Infof("Creating new base image: %s", image)
	if err := files.Copy(cachedImage, image); err != nil {
		return "", fmt.Errorf("failed to create new base image %s, %s", image, err)
	}
	logger.Infof("Created new base image")
	if from.ResizeGB > 0 {
		logger.Infof("Resizing %s to %s\n", image, from.ResizeGB)
		if err := ctx.GetBinary("qemu-img")("resize\"%s\" %sgb", image, from.ResizeGB); err != nil {
			return "", fmt.Errorf("error resizing disk  %s", err)
		}
	}
	return image, nil
}

func createIso(config *konfigadm.Config) (string, error) {
	cloud_init := config.ToCloudInit()

	// if config.Context.CaptureLogs != "" {
	// 	cloud_init.Runcmd = append([][]string{[]string{"bash", "-x", "-c", "mkdir /scratch; mount /dev/sdb1 /scratch"}}, cloud_init.Runcmd...)
	// }
	// if config.Context.CaptureLogs != "" && (config.Cleanup == nil || !*config.Cleanup) {
	// 	cloud_init.Runcmd = append(cloud_init.Runcmd, []string{"bash", "-x", "-c", strings.Join(CaptureLogCommands(), "; ")})
	// }

	logger.Tracef(cloud_init.String())
	// PowerState is once per instance and cloud-init clean (creating a new instance) fails on ubuntu 18.04:
	// IsADirectory: /var/lib/cloud/instance
	//	"cloud_init.PowerState.Mode = "poweroff"
	// so we append a shutdown manually
	cloud_init.Runcmd = append(cloud_init.Runcmd, []string{"shutdown", "-h", "now"})
	return cloudinit.CreateISO("builder", cloud_init.String())
}

func (q Qemu) downloadImage(ctx pkg.BuildContext, image string) string {
	if !strings.HasPrefix(image, "http") {
		return image
	}
	home, _ := os.UserHomeDir()
	imageCache := home + "/.konfigadm/images"
	basename := path.Base(image)
	cachedImage := imageCache + "/" + basename
	if files.Exists(cachedImage) {
		// TODO(moshloop) verify SHASUM
		logger.Infof("Image found in cache: %s", basename)
	} else {
		logger.Infof("Downloading image %s", image)
		if err := os.MkdirAll(imageCache, 0755); err != nil {
			logger.Fatalf("Failed to create cache dir %s", imageCache)
		}
		if err := ctx.GetBinary("wget")("--no-check-certificate -nv -O %s %s", cachedImage, image); err != nil {
			logger.Fatalf("Failed to download image %s, %s", image, err)
		}
	}
	return cachedImage
}

func (q Qemu) clone(ctx pkg.BuildContext, image string) (string, error) {
	if strings.HasPrefix(image, "http") {
		image = q.downloadImage(ctx, image)
	}

	image, err := q.copyImage(ctx, image)
	if err != nil {
		return "", err
	}

	if !files.Exists(image) {
		return "", fmt.Errorf("%s does not exists", image)
	}
	return image, nil
}
