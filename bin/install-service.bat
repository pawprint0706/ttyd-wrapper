@echo off
setlocal EnableExtensions

:: ============================================================
::  ttyd-wrapper Windows Service Installer (via NSSM)
::  Usage:  install-service.bat        (interactive install + start)
::          install-service.bat /dry   (print commands only, no prompts)
::
::  You are asked (in the elevated window) whether to enable a persistent
::  session, HTTPS and login. Pre-set ENABLE_SESSION (y/n) / CRED /
::  SSL_CERT / SSL_KEY below to skip those prompts.
::
::  Persistent sessions use psmux (https://github.com/psmux/psmux) - the
::  session survives disconnects and is mirrored to every device. Install
::  it first with: winget install psmux
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
:: Session name for persistent (psmux) sessions.
if not defined SESSION set "SESSION=%TTYD_SESSION%"
if "%SESSION%"=="" set "SESSION=ttyd"
:: Optional: pre-set to skip the interactive prompts. Leave blank to be asked.
:: ENABLE_SESSION: y/n - persistent session via psmux (see header).
:: Pre-set here OR via the environment (inherited like the other TTYD_* vars;
:: TTYD_PMUX=0 forces it off, mirroring the Unix TTYD_TMUX=0).
if "%TTYD_PMUX%"=="0" set "ENABLE_SESSION=0"
:: Accept y/n presets too (kept for the interactive prompts below).
if /i "%ENABLE_SESSION%"=="y" set "ENABLE_SESSION=1"
if /i "%ENABLE_SESSION%"=="n" set "ENABLE_SESSION=0"
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

:: ---------- Detect psmux (optional persistent session) ----------
:: Bake the absolute path into the service cmdline - the service does not
:: inherit the user PATH, and the launcher only re-resolves it for itself.
:: Honors TTYD_PMUX=0 the same way the manual launcher does.
set "PSMUX="
if not "%TTYD_PMUX%"=="0" for /f "delims=" %%p in ('where psmux.exe 2^>nul') do if not defined PSMUX set "PSMUX=%%p"

set "DRYRUN=0"
if /i "%~1"=="/dry" set "DRYRUN=1"
:: Derive the session choice for /dry (a real install asks interactively).
if "%DRYRUN%"=="1" if not defined ENABLE_SESSION (
    if defined PSMUX ( set "ENABLE_SESSION=1" ) else ( echo [DRY] psmux not detected - install with: winget install psmux & set "ENABLE_SESSION=0" )
)

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
    echo   Session : %SPAWN_CMD%
    echo   Auth    : cred=[%CRED%]  scheme=%SCHEME%
    echo.
    echo [DRY RUN] Commands that would be executed:
    echo   "%NSSM%" install %SERVICE_NAME% "%PSEXE%"
    echo   "%NSSM%" set %SERVICE_NAME% AppParameters -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%LAUNCHER%" --writable -t platform=windows%OPTS% -p %PORT% -I "%INDEX%" --cwd "%SHELL_CWD%" %SPAWN_CMD%
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
echo.
:: Session persistence prompt (skipped if ENABLE_SESSION is pre-set in Configuration)
if defined ENABLE_SESSION goto :after_session
echo   [Session persistence] psmux keeps your shell (and running programs) alive
echo           across disconnects; reconnecting restores it and multiple devices
echo           mirror the same session. Requires 'psmux' (psmux/psmux on GitHub).
if defined PSMUX (
    set /p "ANS_S=  Enable persistent session? [Y/n]: "
) else (
    echo           psmux not detected - install it with: winget install psmux
    set /p "ANS_S=  Enable persistent session? [y/N]: "
)
if not defined ANS_S if defined PSMUX set "ANS_S=y"
if not defined ANS_S set "ANS_S=n"
if /i "%ANS_S%"=="y" ( set "ENABLE_SESSION=1" ) else ( set "ENABLE_SESSION=0" )
:after_session
if /i "%ENABLE_SESSION%"=="y" set "ENABLE_SESSION=1"
if /i "%ENABLE_SESSION%"=="n" set "ENABLE_SESSION=0"
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
:ask_login
set /p "CRED_USER=    Username: "
set /p "CRED_PASS=    Password: "
:: cmd re-expands these values later (echo/if/AppParameters), so any of
:: ^& ( ) percent quotemark angle-pipe or space would corrupt the script
:: mid-install. Verify via PowerShell (env vars skip the parser) and re-ask.
:: IndexOfAny char codes: space 32, quote 34, ampersand 38, parens 40/41,
:: lt/gt 60/62, pipe 124, exclamation 33, caret 94, percent 37.
powershell -NoProfile -Command "exit ([int]((($env:CRED_USER + ':' + $env:CRED_PASS).IndexOfAny([char[]]@(32,34,38,40,41,60,62,124,33,94,37))) -ge 0))" >nul
if "%errorlevel%"=="0" set "CRED=%CRED_USER%:%CRED_PASS%"
if "%errorlevel%"=="0" goto :after_login
echo         [WARN] Username/password contains a character the batch installer
echo                cannot carry safely (ampersand, parenthesis, percent, quote,
echo                lt/gt, pipe, exclamation, caret, space). Pick a plain one
echo                and re-enter.
goto :ask_login
:after_login
echo.

:: Rebuild flags from the selections and validate certificate files.
call :build_opts

:: Pre-flight: session persistence needs psmux (stop before installing anything,
:: matching the Linux/macOS package pre-flight).
if "%ENABLE_SESSION%"=="1" if not defined PSMUX (
    echo [ERROR] Persistent session needs psmux, which was not found.
    echo         Install it first, then re-run this installer:
    echo           winget install psmux
    echo         scoop / choco / cargo also work - see github.com/psmux/psmux
    pause & exit /b 1
)
if defined SSL_CERT if defined SSL_KEY (
    if not exist "%SSL_CERT%" ( echo [ERROR] Certificate not found: %SSL_CERT% & echo         Obtain a cert first ^(acme.sh/certbot + DDNS domain^), then re-run. & pause & exit /b 1 )
    if not exist "%SSL_KEY%"  ( echo [ERROR] Private key not found: %SSL_KEY% & pause & exit /b 1 )
)

echo === Installing ===
echo   Service : %SERVICE_NAME%
echo   Binary  : %TTYD%
echo   Port    : %PORT%
echo   Session : %SPAWN_CMD%
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

"%NSSM%" set "%SERVICE_NAME%" AppParameters -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%LAUNCHER%" --writable -t platform=windows%OPTS% -p %PORT% -I "%INDEX%" --cwd "%SHELL_CWD%" %SPAWN_CMD%
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
:: Spawn command: persistent psmux session when chosen and available,
:: otherwise a fresh PowerShell per connection (as before).
set "SPAWN_CMD=%SHELL_CMD%"
if "%ENABLE_SESSION%"=="1" if defined PSMUX set "SPAWN_CMD="%PSMUX%" new -A -s %SESSION%"
goto :eof
