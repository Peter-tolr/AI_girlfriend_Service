@echo off
chcp 65001 >nul
setlocal
title AICompanion - Start
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1" %*
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
    echo.
    echo [ERROR] Start failed, exit code %CODE%.
    echo Please read the messages above.
    pause
)
endlocal
