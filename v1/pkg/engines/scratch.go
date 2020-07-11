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
	"io/ioutil"
	"os"
	"runtime"

	"github.com/flanksource/commons/deps"
	"github.com/flanksource/commons/logger"
)

var hdiutil = deps.Binary("hdiutil", "", "")

type Scratch interface {
	Create() error
	UnwrapToDir(dir string) error
	GetImg() string
}

type DarwinScratch struct {
	img string
}

func NewScratch() Scratch {
	var scratch Scratch
	if runtime.GOOS == "darwin" {
		scratch = &DarwinScratch{}
	}
	scratch.Create()
	return scratch
}
func (s *DarwinScratch) GetImg() string {
	return s.img
}
func (s *DarwinScratch) Create() error {
	tmp, _ := ioutil.TempFile("", "scratch*.img")
	s.img = tmp.Name()
	logger.Infof("Creating %s", s.img)
	if err := hdiutil("create -fs FAT32 -size 100m -volname scratch %s", s.img); err != nil {
		return err
	}
	return os.Rename(s.img+".dmg", s.img)
}

func (s *DarwinScratch) UnwrapToDir(dir string) error {
	os.MkdirAll(dir, 0755)
	mount, _ := ioutil.TempDir("", "mount")
	if err := hdiutil("attach -mountpoint %s  %s ", mount, s.img); err != nil {
		return err
	}
	defer hdiutil("detach %s", mount)
	return deps.Binary("cp", "", "")("-r %s/* %s", mount, dir)
}

func CaptureLogCommands() []string {
	return []string{
		"mkdir -p /scratch",
		"journalctl  -b --no-hostname -o short > /scratch/journal.log",
		"cp -r /var/log/ /scratch || true",
		"cp -r /var/lib/cloud/ /scratch || true",
	}
}
