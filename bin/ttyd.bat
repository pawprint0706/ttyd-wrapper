@echo off
setlocal EnableExtensions
:: Manual run: relay a persistent psmux session (or a plain PowerShell) over the web.
:: Optional: set CRED for basic auth, SSL_CERT/SSL_KEY for HTTPS.
:: Session overrides: TTYD_SESSION names the session (default "ttyd"),
:: TTYD_PMUX=0 forces a plain PowerShell (no persistence).
:: Keep these in sync with bin\install-service.bat.

:: ---------- Configuration ----------
set "PORT=33322"
set "CRED="
set "SSL_CERT="
set "SSL_KEY="
:: -----------------------------------

set "TTYD=%~dp0ttyd.exe"
set "INDEX=%~dp0..\public\index.html"
set "SESSION=%TTYD_SESSION%"
if "%SESSION%"=="" set "SESSION=ttyd"

set "OPTS="
if defined CRED set "OPTS=%OPTS% -c %CRED%"
if defined SSL_CERT if defined SSL_KEY set "OPTS=%OPTS% -S -C "%SSL_CERT%" -K "%SSL_KEY%""

:: Persistent session: psmux (https://github.com/psmux/psmux, winget install)
:: keeps the shell (and its programs) alive across disconnects and mirrors it
:: to every connected device. Falls back to a plain PowerShell when psmux is
:: absent or TTYD_PMUX=0.
set "PMUX="
if not "%TTYD_PMUX%"=="0" for /f "delims=" %%p in ('where psmux.exe 2^>nul') do if not defined PMUX set "PMUX=%%p"

set "CMD=powershell.exe"
if defined PMUX set "CMD="%PMUX%" new -A -s %SESSION%"

"%TTYD%" --writable -t platform=windows%OPTS% -p %PORT% -I "%INDEX%" --cwd "%USERPROFILE%" %CMD%
