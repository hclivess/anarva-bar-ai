@echo off
rem Double-click to install Anarva into Beyond All Reason. Arguments are passed on to install.ps1:
rem   install.cmd "D:\Games\Beyond-All-Reason\data"    install.cmd -Uninstall    install.cmd -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set ANARVA_EXIT=%ERRORLEVEL%
echo.
pause
exit /b %ANARVA_EXIT%
