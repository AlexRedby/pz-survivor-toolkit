@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch.ps1" -Profile Vanilla %*
set "result=%ERRORLEVEL%"
if not "%result%"=="0" pause
exit /b %result%
