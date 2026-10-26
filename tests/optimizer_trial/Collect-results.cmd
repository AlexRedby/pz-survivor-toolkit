@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-TrialResults.ps1" -PackageRoot "%~dp0." %*
set "result=%ERRORLEVEL%"
pause
exit /b %result%
