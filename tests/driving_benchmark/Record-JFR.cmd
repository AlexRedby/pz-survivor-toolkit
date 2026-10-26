@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Record-JFR.ps1" %*
set "result=%ERRORLEVEL%"
pause
exit /b %result%
