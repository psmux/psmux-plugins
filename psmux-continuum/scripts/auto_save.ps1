#!/usr/bin/env pwsh
# psmux-continuum: Background auto-save loop
param(
    [int]$IntervalMinutes = 15
)

$ErrorActionPreference = 'Continue'

# --- Single-instance guard -------------------------------------------------
# The client-attached hook in plugin.conf fires on EVERY attach, so without a
# guard a new auto-save loop would spawn on each attach and never exit, leaving
# dozens of pwsh processes running (issue #24). A named mutex keeps a single
# auto-save loop per user session; later instances exit immediately. If the
# previous owner was killed the mutex is abandoned and we reclaim it.
$mutex = New-Object System.Threading.Mutex($false, 'Local\psmux-continuum-autosave')
try {
    $haveLock = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $haveLock = $true
}
if (-not $haveLock) {
    exit 0
}

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

# Find the resurrect save script
$saveScript = Join-Path $PSScriptRoot '..\..\psmux-resurrect\scripts\save.ps1'
if (-not (Test-Path $saveScript)) {
    $saveScript = Join-Path $env:USERPROFILE '.psmux\plugins\psmux-resurrect\scripts\save.ps1'
}

if (-not (Test-Path $saveScript)) {
    Write-Host "psmux-continuum: psmux-resurrect not found. Install it first." -ForegroundColor Red
    exit 1
}

$IntervalSeconds = $IntervalMinutes * 60

try {
    while ($true) {
        Start-Sleep -Seconds $IntervalSeconds

        # Check if psmux server is still running.
        # NOTE: psmux returns exit 0 with EMPTY output when no server exists, so the
        # exit-code check alone never fires -- the loop would run forever and (without the
        # resurrect 0-session guard) drive empty-snapshot writes. Treat empty output as
        # "no server" too. ($sessions is only used for this liveness check, never saved.)
        $sessions = & $PSMUX ls 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or -not $sessions.Trim()) {
            Write-Host "psmux-continuum: No psmux server, stopping auto-save." -ForegroundColor Yellow
            break
        }

        # Run the save
        & pwsh -NoProfile -File $saveScript
        Write-Host "psmux-continuum: Auto-saved at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
    }
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
