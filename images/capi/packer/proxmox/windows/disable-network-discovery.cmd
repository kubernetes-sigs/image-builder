reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff /f
netsh advfirewall firewall set rule group="Network Discovery" new enable=No