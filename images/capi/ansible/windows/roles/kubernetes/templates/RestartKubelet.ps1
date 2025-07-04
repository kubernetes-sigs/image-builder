# Copyright 2025 The Kubernetes Authors.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Need to keep sync with StartKubelet.ps1
$FileContent = Get-Content -Path "$env:SYSTEMDRIVE/var/lib/kubelet/kubeadm-flags.env"
$kubeAdmArgs = $FileContent.TrimStart('KUBELET_KUBEADM_ARGS=').Trim('"')

$args = "--cert-dir=$env:SYSTEMDRIVE/var/lib/kubelet/pki",
        "--config=$env:SYSTEMDRIVE/var/lib/kubelet/config.yaml",
        "--bootstrap-kubeconfig=$env:SYSTEMDRIVE/etc/kubernetes/bootstrap-kubelet.conf",
        "--kubeconfig=$env:SYSTEMDRIVE/etc/kubernetes/kubelet.conf",
        "--hostname-override=$(hostname)",
        "--pod-infra-container-image=`"{{ pause_image }}`"",
        "--enable-debugging-handlers",
        "--cgroups-per-qos=false",
        "--enforce-node-allocatable=`"`"",
        "--resolv-conf=`"`"",
        "--windows-service"

$KubeletArgListStr = ($args -join " ") + " $kubeAdmArgs"
$KubeletArgListStr = $KubeletArgListStr.Replace("`"", "\`"")
# Used by sc.exe to create the service 
$KubeletCommandLine =  "`"" + "\`"" + "$env:SYSTEMDRIVE\k\kube-log-runner.exe" + "\`" " + "--log-file=/var/log/kubelet/kubelet.err.log " + "$env:SYSTEMDRIVE\k\kubelet.exe " + $KubeletArgListStr + "`""

# Write-Output $kubeletCommandLine
$null = sc.exe stop kubelet
$null = sc.exe delete kubelet
for ($i = 0; $i -lt 10; $i++) {
	$service = Get-Service -Name kubelet -ErrorAction SilentlyContinue
	if ($null -eq $service) {
		Write-Host "kubelet service deleted successfully, restarting"
		sc.exe create kubelet binPath= $KubeletCommandLine start= auto depend= containerd
		sc.exe start kubelet
		return
	}
	else {
		Write-Host "Waiting for service to be fully deleted... (attempt $($i + 1)/10)"
	}
	Start-Sleep -Seconds 3
}


Write-Host "kubelet service failed to restart."
