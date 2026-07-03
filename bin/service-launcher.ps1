# ============================================================
#  ttyd-wrapper service launcher
#
#  Runs under LocalSystem (NSSM). Resolves the owning user's
#  environment FRESH at every service start - so PATH changes
#  never require re-running the installer - then starts ttyd
#  with the arguments passed through by NSSM.
#
#  User identity comes from two STABLE values baked once by
#  install-service.bat:
#    TTYD_USER_SID      e.g. S-1-5-21-...-1001
#    TTYD_USER_PROFILE  e.g. C:\Users\alice
# ============================================================

$ErrorActionPreference = 'Continue'

$sid  = $env:TTYD_USER_SID
$prof = $env:TTYD_USER_PROFILE

# --- User profile paths (stable, but point tools at the user, not SYSTEM) ---
if ($prof -and (Test-Path -LiteralPath $prof)) {
    $env:USERPROFILE  = $prof
    $env:APPDATA      = Join-Path $prof 'AppData\Roaming'
    $env:LOCALAPPDATA = Join-Path $prof 'AppData\Local'
}

# --- Machine PATH (REG_EXPAND_SZ, auto-expanded) ---
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')

# --- User PATH: read fresh from the user's registry hive ---
$userPath = $null
if ($sid) {
    $hiveKey = "Registry::HKEY_USERS\$sid\Environment"
    $loadedHere = $false

    if (-not (Test-Path $hiveKey) -and $prof) {
        # Hive not loaded (service started before user logon) - load it briefly
        reg.exe load "HKU\$sid" (Join-Path $prof 'NTUSER.DAT') *> $null
        $loadedHere = ($LASTEXITCODE -eq 0)
    }

    if (Test-Path $hiveKey) {
        # REG_EXPAND_SZ values expand against OUR process env; USERPROFILE
        # was pointed at the user above, so %USERPROFILE% expands correctly.
        $userPath = (Get-ItemProperty -Path $hiveKey -Name Path -ErrorAction SilentlyContinue).Path
    }

    if ($loadedHere) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        reg.exe unload "HKU\$sid" *> $null
    }
}

$env:Path = if ($userPath) { "$machinePath;$userPath" } else { $machinePath }

# --- Run ttyd with the pass-through arguments; propagate its exit code ---
& (Join-Path $PSScriptRoot 'ttyd.exe') @args
exit $LASTEXITCODE
