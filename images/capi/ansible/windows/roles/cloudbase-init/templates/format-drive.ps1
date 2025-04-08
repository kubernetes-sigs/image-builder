$DriveLetter = "M"
$Label = "cidata"
$metadata = "meta-data"
$userdata = "user-data"
$metadataPath = "${DriveLetter}:\${metadata}"
$userdataPath = "${DriveLetter}:\${userdata}"
$logfile = "$env:SystemRoot\OEM\SetupComplete2_test.log"

# Find the first uninitialized disk
$UninitializedDisk = Get-Disk | Where-Object PartitionStyle -EQ "Raw" | Select-Object -First 1

if ($UninitializedDisk) {
    $DiskNumber = $UninitializedDisk.Number

    Initialize-Disk -Number $DiskNumber -PartitionStyle MBR
    $Partition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
    Format-Volume -DriveLetter $Partition.DriveLetter -FileSystem FAT32 -NewFileSystemLabel $Label -Confirm:$false
    Set-Partition -DriveLetter $Partition.DriveLetter -NewDriveLetter $DriveLetter

    # Create a YAML file with the hostname 
    # This is required to set up the NoCloud service.  It isn't really used currently but needs to be valid yaml
    # otherwise the service activation fails and UserData Cloud config plugin will not run
    $Hostname = $env:COMPUTERNAME
    "hostname: $Hostname" | Out-File -Encoding ASCII -FilePath $metadataPath

    # move the custom data that was provisioned via Azure to the drive so cloud base can process it
    cp c:\AzureData\CustomData.bin $userdataPath

    $LogMessage = "Formated and configured disk $DiskNumber as $DriveLetter with $Label"
    $LogMessage | Out-File -FilePath $logfile  -Append -Encoding UTF8 
} else {
    $LogMessage = "No uninitialized disks found. Cloudbase-init may not run"
    $LogMessage | Out-File -FilePath $logfile -Append -Encoding UTF8
}
