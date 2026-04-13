
<#
    Install-MSI function adapted from:
    https://github.com/fansec/proxmox_dev/blob/main/packer/win2019/mount/Install-Agent.ps1

    Original Copyright:
    Copyright (c) fansec

    Licensed under the MIT License:
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.

    Modifications by: Martin Sanchez 2025
#>
#Start Transcript 

$transcriptPath = "C:\Logs\Install-Transcript-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath -Append

# Define paths to the installers

$virtio = "virtio-win-gt-x64.msi"
$qemuGuestAgent = "qemu-ga-x86_64.msi"
$logDirectory = "C:\Logs\"

# Ensure the log directory exists
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force
}

# Function to install MSI packages
function Install-MSI {
    param (
        [string]$msiPath,
        [string]$logFile
    )

    if (Test-Path -Path $msiPath) {
        Write-Host "Installing $msiPath"
        Start-Process msiexec -Wait -ArgumentList @('/i', $msiPath, '/log', $logFile, '/qn', '/passive', '/norestart', 'ADDLOCAL=ALL')
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$msiPath installed successfully."
        } else {
            Write-Host "Failed to install $msiPath. Check log file: $logFile"
        }
    } else {
        Write-Host "MSI path $msiPath not found."
    }
}
function Find-DriverFile {
    param (
        [string]$fileName
    )

    #Try D: first
    $path = Get-ChildItem -Path "D:\" -Recurse -Filter $fileName -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName -First 1

    if ($path) {
        return $path
    }

    Write-Host "File '$fileName' not found on D:. Searching all drives..."

    #Search ALL drives except D:
    $allDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne 'D' }

    foreach ($drive in $allDrives) {
        $path = Get-ChildItem -Path ($drive.Root) -Recurse -Filter $fileName -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName -First 1

        if ($path) {
            return $path
        }
    }

    return $null
}
# Install Virtio Drivers
$virtioDriverPath = Find-DriverFile -fileName $virtio
$qemuGuestAgentPath = Find-DriverFile -fileName $qemuGuestAgent

$qemuGuestAgentPath = "D:\guest-agent\qemu-ga-x86_64.msi"
Install-MSI -msiPath $virtioDriverPath -logFile "$logDirectory\qemu-drivers.log"

# Install QEMU Guest Agent
Install-MSI -msiPath $qemuGuestAgentPath -logFile "$logDirectory\qemu-guest-agent.log"

Stop-Transcript