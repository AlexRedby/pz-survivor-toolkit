@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Trial.ps1" -Mode Optimized %*
set "result=%ERRORLEVEL%"
if not "%result%"=="0" pause
exit /b %result%
