function Get-Second-Vnic-Ocid() {
    $ocid = ""
    $vnics = Invoke-RestMethod -Uri "http://169.254.169.254/opc/v1/vnics/"
    if ($vnics.Count -eq 2) {
        $ocid = $vnics[1].vnicId
    } else {
        Write-Host "vnics count not equal 2"
    }
    return $ocid
}

$vnicId = Get-Second-Vnic-Ocid
Write-Host "found vnic id: ${vnicId}"


$retryDelaySeconds = 30
# We should continue to retry indefinitely until the vnic is 
# detected by IMDS 
# https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/gettingmetadata.htm
while($vnicId -eq "") {
    $vnicId = Get-Second-Vnic-Ocid
    Write-Host("Getting second vnic failed. Waiting " + $retryDelaySeconds + " seconds before next attempt.")
    Start-Sleep -Seconds $retryDelaySeconds
}

if ($vnicId -ne "") {
    Write-Host "Pulling down the secondary_vnic_windows_configure.ps1"
    Invoke-WebRequest -Uri "https://docs.oracle.com/en-us/iaas/Content/Resources/Assets/secondary_vnic_windows_configure.ps1" -OutFile "C:\Users\opc\secondary_vnic_windows_configure.ps1"

    Write-Host "calling script using ${vnicId}"

    , 'Y', 'A' | powershell "C:\Users\opc\secondary_vnic_windows_configure.ps1 ${vnicId}"
    Write-Error "secondary_vnic_windows_configure.ps1 - done"

    $ipconfig = ipconfig
    Write-Error "${ipconfig}"
}else{
    Write-Error "VNIC OCID is empty. Can't configure."
}