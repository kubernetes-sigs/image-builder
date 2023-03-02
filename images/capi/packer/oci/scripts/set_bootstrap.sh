#!/usr/bin/env bash
# Copyright 2021 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script overrides the 'opc' password set in the winrm_bootstrap.txt file
# This script is assumed to be run from the make file hence the pathing to the winrm_bootstrap.txt

set -o errexit
set -o nounset
set -o pipefail

echo "Changing Password in winrm_bootstrap.txt"

sed "s/(\[adsi\].*/([adsi](\"WinNT:\/\/\"+\$opcUser.caption).replace(\"\\\\\",\"\/\")).SetPassword(\"$OPC_USER_PASSWORD\")/g" packer/oci/scripts/winrm_bootstrap_template.txt | tee packer/oci/scripts/winrm_bootstrap.txt >/dev/null
