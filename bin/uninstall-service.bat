@echo off
setlocal EnableExtensions

:: ============================================================
::  ttyd-wrapper Windows Service Uninstaller
:: ============================================================

set "SERVICE_NAME=ttyd-wrapper"
set "BIN_DIR=%~dp0"
if "%BIN_DIR:~-1%"=="\" set "BIN_DIR=%BIN_DIR:~0,-1%"
set "NSSM=%BIN_DIR%\nssm.exe"

if not exist "%NSSM%" ( echo [ERROR] nssm.exe not found: %NSSM% & pause & exit /b 1 )

:: ---------- Elevation check ----------
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

sc query "%SERVICE_NAME%" >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Service "%SERVICE_NAME%" is not installed. Nothing to do.
    pause
    exit /b 0
)

echo Stopping and removing service "%SERVICE_NAME%"...
"%NSSM%" stop "%SERVICE_NAME%" >nul 2>&1
"%NSSM%" remove "%SERVICE_NAME%" confirm

netsh advfirewall firewall delete rule name="%SERVICE_NAME%" >nul 2>&1
echo Firewall rule removed.

:: Undo the psmux default-command block added by install-service.bat, so
:: panes don't keep pointing at a removed wrapper.
if exist "%BIN_DIR%\configure-psmux.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%BIN_DIR%\configure-psmux.ps1" -Remove

echo.
echo [OK] Service uninstalled.
pause
