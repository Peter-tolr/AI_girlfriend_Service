@echo off
chcp 65001 >nul
setlocal
title AICompanion - Setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1" %*
echo.
pause
endlocal
