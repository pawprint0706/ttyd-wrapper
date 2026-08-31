# ============================================================
#  shell-env-repair.ps1 - psmux default-command wrapper for the
#  ttyd-wrapper service.
#
#  WHY THIS EXISTS
#  psmux rebuilds each pane's environment from the registry of the
#  spawning token instead of inheriting the server's environment.
#  The ttyd-wrapper service runs as LocalSystem, so panes get
#  HKLM PATH + HKU\S-1-5-18 (SYSTEM's own HKCU) - the terminal
#  user's HKCU PATH (scoop shims, .local\bin, npm, ...) is dropped.
#
#  FIX
#  Set as psmux's default-command (see install-service.bat); it
#  re-resolves the owning user's PATH the same way service-
#  launcher.ps1 does, then hands off to an interactive shell.
#
#  Outside the service (TTYD_USER_SID unset, e.g. desktop psmux)
#  there is nothing to repair - it just launches the shell.
# ============================================================

$ErrorActionPreference = 'Continue'

if ($env:TTYD_USER_SID) {
    # Machine PATH (REG_EXPAND_SZ, auto-expanded)
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')

    # User PATH: raw REG_EXPAND_SZ, expanded against OUR env - USERPROFILE
    # arrives pointed at the terminal user (set by service-launcher.ps1).
    $userPath = $null
    $key = [Microsoft.Win32.Registry]::Users.OpenSubKey("$env:TTYD_USER_SID\Environment")
    if ($key) {
        $raw = $key.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $key.Close()
        if ($raw) { $userPath = [Environment]::ExpandEnvironmentVariables($raw) }
    }

    if ($userPath) {
        $env:Path = "$machinePath;$userPath"
    } else {
        Write-Output "shell-env-repair: WARNING - could not read user hive ($env:TTYD_USER_SID); PATH may be incomplete"
    }
}

# Hand off to an interactive shell (psmux default is pwsh; fall back to
# Windows PowerShell where pwsh is unavailable).
$shell = Get-Command pwsh -ErrorAction SilentlyContinue
if ($shell) { & pwsh -NoLogo } else { & powershell -NoLogo }
exit $LASTEXITCODE