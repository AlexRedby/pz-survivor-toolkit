@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-WPR.ps1" %*
set "result=%ERRORLEVEL%"
pause
exit /b %result%
