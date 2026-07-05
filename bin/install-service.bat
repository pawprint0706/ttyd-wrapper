@echo off
setlocal EnableExtensions

:: ============================================================
::  ttyd-wrapper Windows Service Installer (via NSSM)
::  Usage:  install-service.bat        (interactive install + start)
::          install-service.bat /dry   (print commands only, no prompts)
::
::  You are asked (in the elevated window) whether to enable HTTPS and
::  login. Pre-set CRED / SSL_CERT / SSL_KEY below to skip those prompts.
::  Persistent background sessions are NOT available on Windows.
::
::  The service runs service-launcher.ps1, which re-resolves the
::  user's PATH from the registry at EVERY service start - so
::  PATH changes never require re-running this installer.
:: ============================================================

:: ---------- Configuration ----------
set "SERVICE_NAME=ttyd-wrapper"
set "SERVICE_DISPLAY=ttyd Web Terminal"
set "PORT=33322"
set "SHELL_CWD=%USERPROFILE%"
set "SHELL_CMD=powershell.exe"
:: Optional: pre-set to skip the interactive prompts. Leave blank to be asked.
set "CRED="
set "SSL_CERT="
set "SSL_KEY="

:: ---------- Path resolution ----------
set "BIN_DIR=%~dp0"
if "%BIN_DIR:~-1%"=="\" set "BIN_DIR=%BIN_DIR:~0,-1%"
for %%i in ("%BIN_DIR%\..") do set "ROOT=%%~fi"
set "NSSM=%BIN_DIR%\nssm.exe"
set "TTYD=%BIN_DIR%\ttyd.exe"
set "LAUNCHER=%BIN_DIR%\service-launcher.ps1"
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "INDEX=%ROOT%\public\index.html"
set "LOG_DIR=%ROOT%\logs"

set "DRYRUN=0"
if /i "%~1"=="/dry" set "DRYRUN=1"

:: Build auth/SSL flags from current config (used for /dry and as defaults).
call :build_opts

:: ---------- Sanity checks ----------
if not exist "%NSSM%"     ( echo [ERROR] nssm.exe not found: %NSSM% & pause & exit /b 1 )
if not exist "%TTYD%"     ( echo [ERROR] ttyd.exe not found: %TTYD% & pause & exit /b 1 )
if not exist "%LAUNCHER%" ( echo [ERROR] service-launcher.ps1 not found: %LAUNCHER% & pause & exit /b 1 )
if not exist "%INDEX%"    ( echo [ERROR] index.html not found: %INDEX% & pause & exit /b 1 )

if "%DRYRUN%"=="1" (
    echo.
    echo === ttyd-wrapper service installer [DRY RUN] ===
    echo   Service : %SERVICE_NAME%
    echo   Port    : %PORT%
    echo   Auth    : cred=[%CRED%]  scheme=%SCHEME%
    echo.
    echo [DRY RUN] Commands that would be executed:
    echo   "%NSSM%" install %SERVICE_NAME% "%PSEXE%"
    echo   "%NSSM%" set %SERVICE_NAME% AppParameters -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%LAUNCHER%" --writable -t platform=windows%OPTS% -p %PORT% -I "%INDEX%" --cwd "%SHELL_CWD%" %SHELL_CMD%
    echo   "%NSSM%" set %SERVICE_NAME% AppEnvironmentExtra "TTYD_USER_SID=<your-sid>" "TTYD_USER_PROFILE=%USERPROFILE%"
    echo   "%NSSM%" set %SERVICE_NAME% AppDirectory "%BIN_DIR%"
    echo   "%NSSM%" start %SERVICE_NAME%
    echo   netsh advfirewall firewall add rule name="%SERVICE_NAME%" dir=in action=allow protocol=TCP localport=%PORT%
    exit /b 0
)

:: ---------- Must run as a real user, not SYSTEM ----------
:: The installer captures YOUR identity (SID + profile) for the launcher.
:: Running it from the web terminal (SYSTEM) would capture the wrong user.
whoami | find /i "nt authority\system" >nul
if "%errorlevel%"=="0" (
    echo [ERROR] Do not run this installer from the web terminal.
    echo         Run it from your own desktop session so it can capture
    echo         your user identity for the service environment.
    pause & exit /b 1
)

:: ---------- Elevation check ----------
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ---------- Interactive feature selection (elevated console) ----------
echo.
echo === Configure ttyd-wrapper ===
echo   [Note] Persistent background sessions are not available on Windows
echo          (no tmux-style reattach for PowerShell). Linux/macOS provide it.
echo.
:: HTTPS prompt (skipped if SSL_CERT is pre-set in Configuration)
if defined SSL_CERT goto :after_https
echo   [HTTPS] Encrypts traffic; needed for safe public exposure and PWA install.
set /p "ANS_H=  Enable HTTPS? [y/N]: "
if /i not "%ANS_H%"=="y" goto :after_https
set /p "SSL_CERT=    Certificate (fullchain .pem) path: "
set /p "SSL_KEY=    Private key (.pem) path: "
:after_https
echo.
:: Login prompt (skipped if CRED is pre-set in Configuration)
if defined CRED goto :after_login
echo   [Login] Single account (basic auth), usable from several devices.
echo           Credentials travel base64 (plaintext) - use together with HTTPS.
set /p "ANS_L=  Enable login? [y/N]: "
if /i not "%ANS_L%"=="y" goto :after_login
set /p "CRED_USER=    Username: "
set /p "CRED_PASS=    Password: "
set "CRED=%CRED_USER%:%CRED_PASS%"
:after_login
echo.

:: Rebuild flags from the selections and validate certificate files.
call :build_opts
if defined SSL_CERT if defined SSL_KEY (
    if not exist "%SSL_CERT%" ( echo [ERROR] Certificate not found: %SSL_CERT% & echo         Obtain a cert first ^(acme.sh/certbot + DDNS domain^), then re-run. & pause & exit /b 1 )
    if not exist "%SSL_KEY%"  ( echo [ERROR] Private key not found: %SSL_KEY% & pause & exit /b 1 )
)

echo === Installing ===
echo   Service : %SERVICE_NAME%
echo   Binary  : %TTYD%
echo   Port    : %PORT%
echo   Shell   : %SHELL_CMD% (cwd: %SHELL_CWD%)
echo   Login   : cred=[%CRED%]   HTTPS: %SCHEME%
echo   Logs    : %LOG_DIR%
echo.

:: ---------- Capture stable user identity ----------
set "USER_SID="
for /f "tokens=2 delims=," %%s in ('whoami /user /fo csv /nh') do set "USER_SID=%%~s"
if not defined USER_SID ( echo [ERROR] Failed to resolve user SID & pause & exit /b 1 )
echo   User SID: %USER_SID%

:: ---------- Remove existing service (idempotent) ----------
sc query "%SERVICE_NAME%" >nul 2>&1
if "%errorlevel%"=="0" (
    echo Existing service found. Removing...
    "%NSSM%" stop "%SERVICE_NAME%" >nul 2>&1
    "%NSSM%" remove "%SERVICE_NAME%" confirm
)

:: ---------- Install ----------
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

"%NSSM%" install "%SERVICE_NAME%" "%PSEXE%"
if not "%errorlevel%"=="0" ( echo [ERROR] nssm install failed & pause & exit /b 1 )

"%NSSM%" set "%SERVICE_NAME%" AppParameters -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%LAUNCHER%" --writable -t platform=windows%OPTS% -p %PORT% -I "%INDEX%" --cwd "%SHELL_CWD%" %SHELL_CMD%
"%NSSM%" set "%SERVICE_NAME%" AppDirectory "%BIN_DIR%"
"%NSSM%" set "%SERVICE_NAME%" DisplayName "%SERVICE_DISPLAY%"
"%NSSM%" set "%SERVICE_NAME%" Description "ttyd web terminal wrapper - relays %SHELL_CMD% over %SCHEME% port %PORT%"
"%NSSM%" set "%SERVICE_NAME%" Start SERVICE_AUTO_START

:: Stable identity only - PATH itself is resolved fresh by the launcher
:: at every service start.
"%NSSM%" set "%SERVICE_NAME%" AppEnvironmentExtra "TTYD_USER_SID=%USER_SID%" "TTYD_USER_PROFILE=%USERPROFILE%"

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
        for /f %%h in ('curl -sk -m 5 -o NUL -w "%%{http_code}" %SCHEME%://localhost:%PORT%/') do (
            if "%%h"=="200" ( echo [OK] HTTP check passed: %SCHEME%://localhost:%PORT%/ ) else ( echo [WARN] HTTP check returned %%h )
        )
    )
    echo.
    echo Access from mobile: %SCHEME%://YOUR_PC_IP:%PORT%/
) else (
    echo [ERROR] Service failed to start. Check %LOG_DIR%\ttyd.log
    pause
    exit /b 1
)

pause
exit /b 0

:: ============================================================
::  Subroutines
:: ============================================================

:build_opts
set "OPTS="
set "SCHEME=http"
if defined CRED if not "%CRED%"==":" set "OPTS= -c %CRED%"
if defined SSL_CERT if defined SSL_KEY (
    set "OPTS=%OPTS% -S -C "%SSL_CERT%" -K "%SSL_KEY%""
    set "SCHEME=https"
)
goto :eof
