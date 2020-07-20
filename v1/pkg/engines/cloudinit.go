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
	"io/ioutil"
	"os"
	"path"

	"github.com/flanksource/commons/deps"
)

var mkisofs = deps.Binary("mkisofs", "", "")

//createCloudInitISO creates a new ISO with the user/meta data and returns a path to the iso
func createCloudInitISO(hostname string, userData string) (string, error) {
	dir, err := ioutil.TempDir("", "cloudinit")
	cwd, _ := os.Getwd()
	defer os.Chdir(cwd)
	if err := os.Chdir(dir); err != nil {
		return "", fmt.Errorf("Failed to chdir %v", err)
	}
	if err != nil {
		return "", fmt.Errorf("Failed to create temp dir %s", err)
	}
	if err := ioutil.WriteFile(path.Join(dir, "user-data"), []byte(userData), 0644); err != nil {
		return "", fmt.Errorf("Failed to save user-data %s", err)
	}

	isoFilename, err := ioutil.TempFile("", "user-data*.iso")
	if err != nil {
		return "", fmt.Errorf("Failed to create temp iso %s", err)
	}

	metadata := fmt.Sprintf("instance-id: \nlocal-hostname: %s", hostname)
	if err := ioutil.WriteFile(path.Join(dir, "meta-data"), []byte(metadata), 0644); err != nil {
		return "", fmt.Errorf("Failed to write metadata %v", err)
	}

	if err := mkisofs("-output %s -volid cidata -joliet -rock user-data meta-data 2>&1", isoFilename.Name()); err != nil {
		return "", err
	}
	info, _ := isoFilename.Stat()
	if info.Size() == 0 {
		return "", fmt.Errorf("Empty iso created")
	}
	return isoFilename.Name(), nil
}
