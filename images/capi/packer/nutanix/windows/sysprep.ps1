# Copyright 2020 The Kubernetes Authors.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Write-Output '>>> Sysprepping VM ...'

Write-Output 'Removing default unattend.xml file...'
if( Test-Path $Env:SystemRoot\system32\Sysprep\unattend.xml ) {
  Remove-Item $Env:SystemRoot\system32\Sysprep\unattend.xml -Force
}

$unattendedXml = "$ENV:ProgramFiles\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml"
$FileExists = Test-Path $unattendedXml

If ($FileExists -eq $True) {
  # Use the Cloudbase-init provided unattend file during install
  Write-Output "Using cloudbase-init unattend file for sysprep: $unattendedXml"
  & $Env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /mode:vm /shutdown /quiet /unattend:$unattendedXml
}else {
  & $Env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /mode:vm /shutdown /quiet
}
