#!/usr/bin/env pwsh
# psmux-continuum: Background auto-save loop
param(
    [int]$IntervalMinutes = 15
)

$ErrorActionPreference = 'Continue'

# --- Single-instance guard -------------------------------------------------
# psmux runs one server process per session and every one of them fires
# client-attached, so without a guard each session would start its own loop
# and each loop would save everything (issue #24). One machine-wide mutex
# keeps a single loop for the whole user; every save covers every session.
#
# A newcomer waits a little for the mutex instead of giving up at once: the
# previous loop notices the last server going away within LIVENESS_SECONDS
# and releases it, so a server restart hands the loop over instead of
# leaving the new server with no auto-save until the next attach (the
# structural point of PR #30). An abandoned mutex (owner force-killed) is
# reclaimed.
$MUTEX_HANDOVER_MS = 20000
$mutex = New-Object System.Threading.Mutex($false, 'Local\psmux-continuum-autosave')
try {
    $haveLock = $mutex.WaitOne($MUTEX_HANDOVER_MS)
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

# @continuum-save-interval wins over the -IntervalMinutes the hook passes,
# so the documented option actually changes the cadence (issue #37). It is
# re-read on every lap so a change made in a running server takes effect
# without a restart; 0 stops the loop.
function Get-SaveIntervalMinutes {
    try {
        $opt = (& $PSMUX show-options -gv '@continuum-save-interval' 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $opt -match '^\d+$') { return [int]$opt }
    } catch {}
    return $IntervalMinutes
}

# Is any psmux server up? Current psmux answers a missing server with exit 1
# and a "no server running" line; older builds returned exit 0 with EMPTY
# output, which an exit-code-only check missed (the loop then ran forever and,
# without the resurrect 0-session guard, drove empty-snapshot writes). Either
# shape means gone. ($sessions is only used for this check, never saved.)
function Test-ServerAlive {
    $sessions = & $PSMUX ls 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $sessions.Trim()) { return $false }
    return $true
}

# The loop sleeps toward the next save in short slices and checks liveness
# between them, so it reaps within seconds of the last server going away
# instead of at the next save tick, and never saves against a dead server.
$LIVENESS_SECONDS = 10

try {
    while ($true) {
        $minutes = Get-SaveIntervalMinutes
        if ($minutes -le 0) {
            Write-Host "psmux-continuum: auto-save disabled (@continuum-save-interval 0)." -ForegroundColor Yellow
            break
        }

        $due = (Get-Date).AddMinutes($minutes)
        $alive = $true
        while ((Get-Date) -lt $due) {
            $remaining = [int][Math]::Ceiling(($due - (Get-Date)).TotalSeconds)
            Start-Sleep -Seconds ([Math]::Max(1, [Math]::Min($LIVENESS_SECONDS, $remaining)))
            if (-not (Test-ServerAlive)) { $alive = $false; break }
        }
        if (-not $alive) {
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
