@echo off
setlocal EnableExtensions
:: Manual run: relay PowerShell over the web on port 33322.
:: Optional: set CRED for basic auth (user:pass) and SSL_CERT/SSL_KEY for HTTPS.
:: Keep these in sync with bin\install-service.bat.

:: ---------- Configuration ----------
set "PORT=33322"
set "CRED="
set "SSL_CERT="
set "SSL_KEY="
:: -----------------------------------

set "TTYD=%~dp0ttyd.exe"
set "INDEX=%~dp0..\public\index.html"

set "OPTS="
if defined CRED set "OPTS=%OPTS% -c %CRED%"
if defined SSL_CERT if defined SSL_KEY set "OPTS=%OPTS% -S -C "%SSL_CERT%" -K "%SSL_KEY%""

"%TTYD%" --writable -t platform=windows%OPTS% -p %PORT% -I "%INDEX%" --cwd "%USERPROFILE%" powershell.exe
