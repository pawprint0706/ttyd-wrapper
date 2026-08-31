# ============================================================
#  configure-psmux.ps1 - wire the ttyd-wrapper pane-environment
#  repair wrapper into the user's psmux config.
#
#  WHY: psmux rebuilds each pane's environment from the spawning
#  token's registry. Under the ttyd-wrapper service that token is
#  LocalSystem, so panes get HKLM PATH + HKU\S-1-5-18 and lose the
#  terminal user's HKCU PATH (scoop shims, .local\bin, npm, ...).
#  psmux's default-command routes every pane through
#  shell-env-repair.ps1, which re-resolves the user PATH first.
#
#  Usage:  configure-psmux.ps1                add (idempotent)
#          configure-psmux.ps1 -Remove        remove (idempotent)
#  -WrapperPath / -ConfPath override the defaults for testing.
# ============================================================

param(
    [string]$WrapperPath = (Join-Path $PSScriptRoot 'shell-env-repair.ps1'),
    [string]$ConfPath    = (Join-Path $env:USERPROFILE '.psmux.conf'),
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$beginMark = '# >>> ttyd-wrapper pane env repair'
$endMark   = '# <<< ttyd-wrapper pane env repair'
# Forward slashes: immune to C-string escaping of \bin etc. by any
# conf parser, and both PowerShell and cmd accept them in paths.
$wrapper = $WrapperPath -replace '\\','/'

$conf = if (Test-Path -LiteralPath $ConfPath) { Get-Content -LiteralPath $ConfPath -Raw } else { $null }

if ($Remove) {
    if (-not $conf -or $conf -notmatch [regex]::Escape($beginMark)) {
        Write-Output "configure-psmux: no ttyd-wrapper block in '$ConfPath' - nothing to remove."
        exit 0
    }
    $kept = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    foreach ($line in (Get-Content -LiteralPath $ConfPath)) {
        if ($line -eq $beginMark) { $inBlock = $true; continue }
        if ($line -eq $endMark)   { $inBlock = $false; continue }
        if (-not $inBlock) { $kept.Add($line) }
    }
    if (($kept -join '').Trim()) {
        Set-Content -LiteralPath $ConfPath -Value $kept
        Write-Output "configure-psmux: removed the ttyd-wrapper block from '$ConfPath'."
    } else {
        Remove-Item -LiteralPath $ConfPath -Force
        Write-Output "configure-psmux: removed '$ConfPath' (only the ttyd-wrapper block was present)."
    }
    exit 0
}

if ($conf -match [regex]::Escape($beginMark)) {
    Write-Output "configure-psmux: ttyd-wrapper block already present in '$ConfPath' - nothing to do."
    exit 0
}
if ($conf -match 'default-command') {
    Write-Output "configure-psmux: SKIPPED - '$ConfPath' already sets default-command so we do not clobber it:"
    Write-Output "  ($((Get-Content -LiteralPath $ConfPath | Select-String 'default-command') -join '; '))"
    Write-Output "  To take the ttyd-wrapper pane env repair, add a block like this yourself:"
    Write-Output ""
    Write-Output '# >>> ttyd-wrapper pane env repair'
    Write-Output "set -g default-command `"powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper`""
    Write-Output '# <<< ttyd-wrapper pane env repair'
    exit 2
}

$block = @"

$beginMark
# psmux rebuilds pane environments from the LocalSystem service
# token's registry (HKLM + HKU/S-1-5-18), which drops the terminal
# user's HKCU PATH. Route every pane through the wrapper that
# re-resolves the user PATH, then starts the interactive shell.
set -g default-command "powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper"
$endMark
"@
Add-Content -LiteralPath $ConfPath -Value $block
Write-Output "configure-psmux: added the ttyd-wrapper pane env repair block to '$ConfPath'."
exit 0