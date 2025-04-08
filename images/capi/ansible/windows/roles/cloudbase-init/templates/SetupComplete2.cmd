@echo off
SETLOCAL enabledelayedexpansion

set SetupLog=%SystemRoot%\OEM\SetupComplete2_test.log

@echo SetupComplete2 test >> %SetupLog%
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File %SystemRoot%\OEM\format-drive.ps1
sc config cloudbase-init start= auto && net start cloudbase-init
@echo SetupComplete2 test complete >> %SetupLog%