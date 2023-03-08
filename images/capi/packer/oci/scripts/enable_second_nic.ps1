
$newNetAdapterName = "Ethernet 2"

# check for two nics
$netAdapters = Get-NetAdapter
if ($netAdapters.Length -le 1) {
    Write-Output "Could not find multiple Network Adapters."
    Exit 1
}

# Make sure we use the second NIC, not the primary
$primaryNic = Get-NetAdapter -Physical -Name "Ethernet"
ForEach ($adapter in $netAdapters){
    if ($adapter.Name -ne $primaryNic.Name) {
        $secondNic = $adapter
    }
}

if ($secondNic -eq $null) {
    Write-Output "Could not find second Network Adapter from ${netAdapters}"
    Exit 1
}

# make sure the network adapter is known
if ($secondNic.Name -ne "") {
    Write-Output "Changing ${secondNic.Name} to ${newNetAdapterName} ..."
    try
    {
        Rename-NetAdapter -Name $secondNic.Name -NewName "${newNetAdapterName}"
        $secondNic.Name = $newNetAdapterName
    }
    catch
    {
        Write-Output "Could not rename net adapter"
        Write-Output $_
    }
} else {
    Write-Output "Can not change network adapter named: ${secondNic.Name}"
}

# check that second is disabled
if ($secondNic.Status -ne "up") {
    
    try
    {
        Enable-NetAdapter -Name $secondNic.Name
        Write-Output "${secondNic.Name} enabled ..."
    }
    catch
    {
        Write-Output "Could not enable net adapter"
        Write-Output $_
    }
} else {
    Write-Output "${secondNic.Name} already enabled ..."
}

Remove-Item -Path .\enable_second_nic.ps1