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
# At boot the service may start while the profile service is still loading
# NTUSER.DAT. A failed load + an unmounted hive would silently drop the
# user PATH (and it sticks - the psmux server freezes it into every
# session it spawns), so wait briefly and retry instead of giving up.
$userPath = $null
if ($sid) {
    $hiveKey = "Registry::HKEY_USERS\$sid\Environment"
    $loadedHere = $false

    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Test-Path $hiveKey) -and (Get-Date) -lt $deadline) {
        if ($prof -and -not $loadedHere) {
            # Hive not loaded (service started before user logon) - load it briefly
            reg.exe load "HKU\$sid" (Join-Path $prof 'NTUSER.DAT') *> $null
            $loadedHere = ($LASTEXITCODE -eq 0)
        }
        if (Test-Path $hiveKey) { break }
        Start-Sleep -Milliseconds 500
    }

    if (Test-Path $hiveKey) {
        # REG_EXPAND_SZ values expand against OUR process env; USERPROFILE
        # was pointed at the user above, so %USERPROFILE% expands correctly.
        $userPath = (Get-ItemProperty -Path $hiveKey -Name Path -ErrorAction SilentlyContinue).Path
        Write-Output "[$(Get-Date -Format s)] launcher: user PATH resolved ($(($userPath -split ';').Count) entries)"
    } else {
        Write-Output "[$(Get-Date -Format s)] launcher: WARNING - user hive unavailable after 15s; shell PATH will lack user entries (machine PATH only)"
    }

    if ($loadedHere) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        reg.exe unload "HKU\$sid" *> $null
    }
}

$env:Path = if ($userPath) { "$machinePath;$userPath" } else { $machinePath }
Write-Output "[$(Get-Date -Format s)] launcher: PATH composed ($($env:Path.Split(';').Count) entries), starting ttyd"

# NOTE: no pre-warm of the psmux session here. A session spawned by this
# LocalSystem service is invisible-or-worse to user-context clients:
# psmux's client-side liveness check (OpenProcess QUERY_LIMITED_INFORMATION
# on the recorded server PID) is denied for SYSTEM-owned server processes,
# so a user-context "psmux ls" mistakes the live server for stale and
# DELETES its registry files. The session is created by the first web
# connect instead (ttyd spawn), which keeps the server lifecycle inside
# the service environment.

# --- Run ttyd with the pass-through arguments; propagate its exit code ---
& (Join-Path $PSScriptRoot 'ttyd.exe') @args
exit $LASTEXITCODE
