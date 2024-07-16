# Copyright 2022 The Kubernetes Authors.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# script modified from https://github.com/Azure/AgentBaker/blob/8d5323f3b1a622d558e624e5a6b0963229f80b2a/staging/cse/windows/configfunc.ps1 under MIT

$ErrorActionPreference = 'Stop'

function Enable-Privilege {
  param($Privilege)
  $Definition = @'
  using System;
  using System.Runtime.InteropServices;
  public class AdjPriv {
    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
      ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr rele);
    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
    [DllImport("advapi32.dll", SetLastError = true)]
    internal static extern bool LookupPrivilegeValue(string host, string name,
      ref long pluid);
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    internal struct TokPriv1Luid {
      public int Count;
      public long Luid;
      public int Attr;
    }
    internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
    internal const int TOKEN_QUERY = 0x00000008;
    internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
    public static bool EnablePrivilege(long processHandle, string privilege) {
      bool retVal;
      TokPriv1Luid tp;
      IntPtr hproc = new IntPtr(processHandle);
      IntPtr htok = IntPtr.Zero;
      retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
        ref htok);
      tp.Count = 1;
      tp.Luid = 0;
      tp.Attr = SE_PRIVILEGE_ENABLED;
      retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
      retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero,
        IntPtr.Zero);
      return retVal;
    }
  }
'@
  $ProcessHandle = (Get-Process -id $pid).Handle
  $type = Add-Type $definition -PassThru
  $type[0]::EnablePrivilege($processHandle, $Privilege)
}

function Aquire-Privilege {
  param($Privilege)

  write-output "Acquiring the $Privilege privilege"
  $enablePrivilegeResponse = $false
  for ($i = 0; $i -lt 10; $i++) {
    write-output "Retry $i : Trying to enable the $Privilege privilege"
    $enablePrivilegeResponse = Enable-Privilege -Privilege "$Privilege"
    if ($enablePrivilegeResponse) {
      break
    }
    Start-Sleep 1
  }
  if (!$enablePrivilegeResponse) {
    write-error "Failed to enable the $Privilege privilege."
    exit 1
  }
}

function Set-RegistryKeyPermissions {
  param (
    [string]$RegistryKeyPath,
    [string]$TargetOwner = "BUILTIN\Administrators"
  )

  try {
    $owner = [System.Security.Principal.NTAccount]$TargetOwner

    # Open the key with permission to take ownership
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
      $RegistryKeyPath,
      [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
      [System.Security.AccessControl.RegistryRights]::TakeOwnership)

    if (-not $key) {
      write-host "Failed to open registry key $RegistryKeyPath. Registry key does not exist."
      return
    }

    # Get ACL and set owner
    $acl = $key.GetAccessControl()
    $originalOwner = $acl.owner
    $acl.SetOwner($owner)
    $key.SetAccessControl($acl)

    # Reopen the key with permission to change permissions
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
      $RegistryKeyPath,
      [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
      [System.Security.AccessControl.RegistryRights]::ChangePermissions)
    $acl = $key.GetAccessControl()

    # Remove any deny permissions
    $RemoveAcl = $acl.Access | Where-Object { $_.AccessControlType -eq "Deny" }
    if ($RemoveAcl) {
      $Acl.RemoveAccessRule($RemoveAcl)
    }

    # Disable protection (enable inheritance)
    $acl.SetAccessRuleProtection($false, $true)  # False disables protection; true preserves existing entries

    # Add a new access rule
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule (
      $owner,
      [System.Security.AccessControl.RegistryRights]::FullControl,
      [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.SetAccessRule($rule)

    # Apply the updated ACL back to the registry key
    $key.SetAccessControl($acl)

    return @{
      OriginalOwner = $originalOwner
      RegistryKey   = $key
      Rule          = $rule
    }
  }
  catch {
    write-error "Failed to set GMSA plugin registry permissions. $_"
    exit 1
  }
}

function Restore-RegistryKeyOriginalAccess {
  param (
    [Microsoft.Win32.RegistryKey]$Key,
    [System.Security.AccessControl.RegistryAccessRule]$Rule,
    [string]$OriginalOwner
  )

  try {
    $acl = $key.GetAccessControl()
    $acl.RemoveAccessRule($rule) | Out-Null
    $acl.SetOwner([System.Security.Principal.NTAccount]$originalowner)

    # Apply the updated ACL to the key
    $key.SetAccessControl($acl)
    $key.close()
  }
  catch {
    Write-Error "Failed to restore original registry access. $_"
    exit 1
  }
}

###############################################################
######################### MAIN SCRIPT #########################
###############################################################

# Check if the registerplugin.reg file exists
$pluginPath = "$PSScriptRoot\registerplugin.reg"
if (-not (Test-Path "$pluginPath")) {
  write-error "Couldn't find file: $pluginPath"
  exit 1
}

# Enable the PowerShell privilege to set the registry permissions
Aquire-Privilege -Privilege "SeTakeOwnershipPrivilege"

# Get the registry key paths from the plugin file to set permissions
[System.Array]$registryKeyPaths = @( "System\CurrentControlSet\Control\CCG\COMClasses" )
$registryKeyPaths += Get-Content -Path $pluginPath | ForEach-Object {
  if ($_ -match '^\[HKEY_LOCAL_MACHINE\\(.*)]$') {
    return $matches[1]
  }
}

[System.Array]$registryResults = @()
try {
  # Set the registry owner and permissions
  Write-Output "Setting registry owner and permissions"
  foreach ($registryKeyPath in $registryKeyPaths) {
    write-output "Setting permissions: { KeyPath: $RegistryKeyPath }"
    $result = Set-RegistryKeyPermissions -RegistryKeyPath "$registryKeyPath"
    $registryResults += $result
  }

  # HACK: Set the error action preference to 'Continue' to avoid script-terminating errors
  # Restore the original error action preference after the registry import is done
  # In Windows PowerShell (v5.1), 2>&1 redirection in the presence of $ErrorActionPreference = 'Stop'
  # generates a script-terminating error if stderr output is written.
  # https://github.com/PowerShell/PowerShell/issues/3996
  # https://www.reddit.com/r/PowerShell/comments/16j43tx/howto_properly_capture_error_output_from_external/
  $ErrorActionPreference = 'Continue'

  # Import the registry values from the plugin file
  Write-Output "Setting the appropriate GMSA plugin registry values"
  $cmdOutput = reg.exe import "$pluginPath" 2>&1

  # Reset the error action preference to 'Stop'
  $ErrorActionPreference = 'Stop'

  if ($LASTEXITCODE -ne 0) {
    throw "Failed to import GMSA plugin registry values. $cmdOutput"
  }
  Write-Output "Successfully imported the GMSA plugin registry values"
}
catch {
  Write-Error "Couldn't install the GMSA plugin. $_"
  exit 1
}
finally {
  # Restore the original registry permissions
  Write-Output "Restoring original access to registry key"

  # Acquire necessary privileges for restoring owner
  Aquire-Privilege -Privilege SeRestorePrivilege

  foreach ($result in $registryResults) {
    Restore-RegistryKeyOriginalAccess -Key $result.RegistryKey -Rule $result.Rule -OriginalOwner $result.OriginalOwner
  }
}


write-output "Successfully installed the GMSA plugin"
