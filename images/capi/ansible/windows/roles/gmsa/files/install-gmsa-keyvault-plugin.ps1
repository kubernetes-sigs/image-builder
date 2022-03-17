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
  $enablePrivilegeResponse=$false
  for($i = 0; $i -lt 10; $i++) {
      write-output "Retry $i : Trying to enable the $Privilege privilege"
      $enablePrivilegeResponse = Enable-Privilege -Privilege "$Privilege" -ErrorAction 'Continue'
      if ($enablePrivilegeResponse) {
          break
      }
      Start-Sleep 1
  }
  if(!$enablePrivilegeResponse) {
      write-output "Failed to enable the $Privilege privilege."
      exit 1
  }
}

# Enable the PowerShell privilege to set the registry permissions.
Aquire-Privilege -Privilege "SeTakeOwnershipPrivilege"

# Set the registry permissions.
write-output "Setting GMSA plugin registry permissions"
try {
    $ccgKeyPath = "System\CurrentControlSet\Control\CCG\COMClasses"
    $owner = [System.Security.Principal.NTAccount]"BUILTIN\Administrators"

    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        $ccgKeyPath,
        [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
        [System.Security.AccessControl.RegistryRights]::TakeOwnership)
    $acl = $key.GetAccessControl()
    $originalOwner = $acl.owner
    $acl.SetOwner($owner)
    $key.SetAccessControl($acl)
    
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        $ccgKeyPath,
        [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
        [System.Security.AccessControl.RegistryRights]::ChangePermissions)
    $acl = $key.GetAccessControl()
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
        $owner,
        [System.Security.AccessControl.RegistryRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow)
    $acl.SetAccessRule($rule)
    $key.SetAccessControl($acl)
} catch {
    write-output "Failed to set GMSA plugin registry permissions. $_"
    exit 1
}

# Set the appropriate registry values.
try {
    write-output "Setting the appropriate GMSA plugin registry values"
    reg.exe import "registerplugin.reg"
} catch {
    write-output "Failed to set GMSA plugin registry values. $_"
    exit 1
}

write-output "Restore original access to registry key"
$acl = $key.GetAccessControl()
$acl.RemoveAccessRule($rule)
$acl.SetOwner([System.Security.Principal.NTAccount]$originalowner)
Aquire-Privilege -Privilege "SeRestorePrivilege"
$key.SetAccessControl($acl)
$key.close()


write-output "Successfully installed the GMSA plugin"
