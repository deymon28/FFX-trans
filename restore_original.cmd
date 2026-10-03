@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore_original.ps1" %*
set "patch_exit=%errorlevel%"
pause
exit /b %patch_exit%
