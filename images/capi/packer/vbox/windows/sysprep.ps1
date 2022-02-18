Write-Output '>>> Sysprepping VM ...'
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
