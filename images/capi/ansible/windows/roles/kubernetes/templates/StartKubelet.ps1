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

# From https://github.com/kubernetes-sigs/sig-windows-tools/blob/master/kubeadm/scripts/PrepareNode.ps1
$FileContent = Get-Content -Path "/var/lib/kubelet/kubeadm-flags.env" -Raw
# Substring strip (not char-set) of the KUBELET_KUBEADM_ARGS="..." wrapper.
$kubeAdmArgs = ($FileContent -replace '(?s)^\s*KUBELET_KUBEADM_ARGS=("?)(.*?)\1\s*$', '$2').Trim()

$argList = @(
    "--cert-dir=$env:SYSTEMDRIVE/var/lib/kubelet/pki",
    "--config=$env:SYSTEMDRIVE/var/lib/kubelet/config.yaml",
    "--bootstrap-kubeconfig=$env:SYSTEMDRIVE/etc/kubernetes/bootstrap-kubelet.conf",
    "--kubeconfig=$env:SYSTEMDRIVE/etc/kubernetes/kubelet.conf",
    "--hostname-override=$(hostname)",
    "--enable-debugging-handlers",
    "--cgroups-per-qos=false",
    '--enforce-node-allocatable=""',
    '--resolv-conf=""'
)
if ($kubeAdmArgs) {
    $argList += $kubeAdmArgs -split '\s+'
}

# Log the resolved command line so failures are diagnosable from the kubelet log dir.
$kubeletExe = "{{ kubernetes_install_path }}\kubelet.exe"
$logDir = "$env:SYSTEMDRIVE\var\log\kubelet"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
"$(Get-Date -Format o) $kubeletExe $($argList -join ' ')" | Out-File -Append -FilePath "$logDir\start-kubelet.log"

# Splat the args so PowerShell does not re-interpret values containing `=`, `:`, `$`, etc.
& $kubeletExe @argList
