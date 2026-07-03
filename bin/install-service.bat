@echo off
setlocal EnableExtensions

:: ============================================================
::  ttyd-wrapper Windows Service Installer (via NSSM)
::  Usage:  install-service.bat        (installs + starts)
::          install-service.bat /dry   (print commands only)
:: ============================================================

:: ---------- Configuration ----------
set "SERVICE_NAME=ttyd-wrapper"
set "SERVICE_DISPLAY=ttyd Web Terminal"
set "PORT=33322"
set "SHELL_CWD=%USERPROFILE%"
set "SHELL_CMD=powershell.exe"

:: ---------- Path resolution ----------
set "BIN_DIR=%~dp0"
if "%BIN_DIR:~-1%"=="\" set "BIN_DIR=%BIN_DIR:~0,-1%"
for %%i in ("%BIN_DIR%\..") do set "ROOT=%%~fi"
set "NSSM=%BIN_DIR%\nssm.exe"
set "TTYD=%BIN_DIR%\ttyd.exe"
set "INDEX=%ROOT%\public\index.html"
set "LOG_DIR=%ROOT%\logs"

set "DRYRUN=0"
if /i "%~1"=="/dry" set "DRYRUN=1"

:: ---------- Sanity checks ----------
if not exist "%NSSM%"  ( echo [ERROR] nssm.exe not found: %NSSM% & pause & exit /b 1 )
if not exist "%TTYD%"  ( echo [ERROR] ttyd.exe not found: %TTYD% & pause & exit /b 1 )
if not exist "%INDEX%" ( echo [ERROR] index.html not found: %INDEX% & pause & exit /b 1 )

echo.
echo === ttyd-wrapper service installer ===
echo   Service : %SERVICE_NAME%
echo   Binary  : %TTYD%
echo   Index   : %INDEX%
echo   Port    : %PORT%
echo   Shell   : %SHELL_CMD% (cwd: %SHELL_CWD%)
echo   Logs    : %LOG_DIR%
echo.

if "%DRYRUN%"=="1" (
    echo [DRY RUN] Commands that would be executed:
    echo   "%NSSM%" install %SERVICE_NAME% "%TTYD%"
    echo   "%NSSM%" set %SERVICE_NAME% AppParameters --writable -p %PORT% -I "%INDEX%" --cwd "%SHELL_CWD%" %SHELL_CMD%
    echo   "%NSSM%" set %SERVICE_NAME% AppDirectory "%BIN_DIR%"
    echo   "%NSSM%" start %SERVICE_NAME%
    echo   "%NSSM%" set %SERVICE_NAME% AppEnvironmentExtra "PATH=..." "USERPROFILE=%USERPROFILE%" "APPDATA=%APPDATA%" "LOCALAPPDATA=%LOCALAPPDATA%"
    echo   netsh advfirewall firewall add rule name="%SERVICE_NAME%" dir=in action=allow protocol=TCP localport=%PORT%
    exit /b 0
)

:: ---------- Elevation check ----------
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ---------- Remove existing service (idempotent) ----------
sc query "%SERVICE_NAME%" >nul 2>&1
if "%errorlevel%"=="0" (
    echo Existing service found. Removing...
    "%NSSM%" stop "%SERVICE_NAME%" >nul 2>&1
    "%NSSM%" remove "%SERVICE_NAME%" confirm
)

:: ---------- Install ----------
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

"%NSSM%" install "%SERVICE_NAME%" "%TTYD%"
if not "%errorlevel%"=="0" ( echo [ERROR] nssm install failed & pause & exit /b 1 )

"%NSSM%" set "%SERVICE_NAME%" AppParameters --writable -p %PORT% -I "%INDEX%" --cwd "%SHELL_CWD%" %SHELL_CMD%
"%NSSM%" set "%SERVICE_NAME%" AppDirectory "%BIN_DIR%"
"%NSSM%" set "%SERVICE_NAME%" DisplayName "%SERVICE_DISPLAY%"
"%NSSM%" set "%SERVICE_NAME%" Description "ttyd web terminal wrapper - relays %SHELL_CMD% over HTTP port %PORT%"
"%NSSM%" set "%SERVICE_NAME%" Start SERVICE_AUTO_START

:: Inject the installing user's environment. The service runs as LocalSystem,
:: which lacks user PATH entries (e.g. %%LOCALAPPDATA%%\omp) and user profile
:: paths, so user-installed CLI tools would be "command not found" otherwise.
"%NSSM%" set "%SERVICE_NAME%" AppEnvironmentExtra "PATH=%PATH%" "USERPROFILE=%USERPROFILE%" "APPDATA=%APPDATA%" "LOCALAPPDATA=%LOCALAPPDATA%"

:: Logging with rotation (1 MB)
"%NSSM%" set "%SERVICE_NAME%" AppStdout "%LOG_DIR%\ttyd.log"
"%NSSM%" set "%SERVICE_NAME%" AppStderr "%LOG_DIR%\ttyd.log"
"%NSSM%" set "%SERVICE_NAME%" AppRotateFiles 1
"%NSSM%" set "%SERVICE_NAME%" AppRotateOnline 1
"%NSSM%" set "%SERVICE_NAME%" AppRotateBytes 1048576

:: Auto-restart on crash (3s delay)
"%NSSM%" set "%SERVICE_NAME%" AppExit Default Restart
"%NSSM%" set "%SERVICE_NAME%" AppRestartDelay 3000

:: ---------- Firewall rule (LAN/mobile access) ----------
netsh advfirewall firewall delete rule name="%SERVICE_NAME%" >nul 2>&1
netsh advfirewall firewall add rule name="%SERVICE_NAME%" dir=in action=allow protocol=TCP localport=%PORT% >nul
if "%errorlevel%"=="0" ( echo Firewall rule added for TCP %PORT% ) else ( echo [WARN] Failed to add firewall rule )

:: ---------- Start + verify ----------
"%NSSM%" start "%SERVICE_NAME%"
timeout /t 3 /nobreak >nul

sc query "%SERVICE_NAME%" | find "RUNNING" >nul
if "%errorlevel%"=="0" (
    echo.
    echo [OK] Service is RUNNING.
    where curl >nul 2>&1 && (
        for /f %%h in ('curl -s -m 5 -o NUL -w "%%{http_code}" http://localhost:%PORT%/') do (
            if "%%h"=="200" ( echo [OK] HTTP check passed: http://localhost:%PORT%/ ) else ( echo [WARN] HTTP check returned %%h )
        )
    )
    echo.
    echo Access from mobile: http://YOUR_PC_IP:%PORT%/
) else (
    echo [ERROR] Service failed to start. Check %LOG_DIR%\ttyd.log
    pause
    exit /b 1
)

pause
