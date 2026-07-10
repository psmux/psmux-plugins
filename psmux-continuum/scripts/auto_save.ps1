#!/usr/bin/env pwsh
# psmux-continuum: auto-save loop that lives and dies with its psmux server.
#
# Lifecycle: resolve the server (see Get-ServerProcess; exit if none), take a
# per-server-pid mutex (one loop per server, so a repeat client-attached fire is a
# no-op), then block-and-save until the server exits. If the server dies WHILE a
# save runs, the loop finishes that save before the next block reaps - so a mid-save
# death delays the reap by up to one save.
param(
    # Save cadence (e.g. 00:15:00).
    [TimeSpan]$Interval = [TimeSpan]::FromMinutes(15),
    # The psmux server process to watch; $null = auto-detect (see Get-ServerProcess).
    [Nullable[int]]$ServerPid = $null
)

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux', 'pmux', 'tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

# Resolve the psmux server process this loop belongs to, so the wait loop below
# can exit the instant it dies. Three tiers, most to least reliable:
#   1. $ServerPid, when a caller passes it - authoritative.
#   2. Our parent process: run-shell spawns this script directly as a child of the
#      server, so the parent IS the server - no psmux call.
#   3. `display-message -p '#{pid}'`, only when the parent isn't a psmux process.
function Get-ServerProcess {
    if ($null -ne $ServerPid) { return Get-Process -Id $ServerPid -ErrorAction SilentlyContinue }
    $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue).ParentProcessId
    if ($parentId) {
        $parent = Get-Process -Id $parentId -ErrorAction SilentlyContinue
        if ($parent -and $parent.ProcessName -in @('psmux', 'pmux', 'tmux')) { return $parent }
    }
    try {
        $queried = [int]((& $PSMUX display-message -p '#{pid}' 2>&1 | Out-String).Trim())
        if ($queried -gt 0) { return Get-Process -Id $queried -ErrorAction SilentlyContinue }
    } catch {}
    return $null
}

$server = Get-ServerProcess
if (-not $server) {
    # Can't identify our server: refuse to run rather than spin a loop that could
    # outlive it and orphan.
    Write-Host "psmux-continuum: could not resolve the psmux server process; auto-save not started." -ForegroundColor Yellow
    exit 0
}

# Force the OS process handle open now, while the pid is known live, so the wait
# loop below tracks THIS process object - not whatever might later reuse the pid.
try { $null = $server.SafeHandle } catch { }

# Find the resurrect save script.
$saveScript = Join-Path $PSScriptRoot '..\..\psmux-resurrect\scripts\save.ps1'
if (-not (Test-Path $saveScript)) {
    $saveScript = Join-Path $env:USERPROFILE '.psmux\plugins\psmux-resurrect\scripts\save.ps1'
}
if (-not (Test-Path $saveScript)) {
    Write-Host "psmux-continuum: psmux-resurrect not found. Install it first." -ForegroundColor Red
    exit 1
}

$cadenceMs = [int]$Interval.TotalMilliseconds

# Single-instance guard (issue #24), keyed to this server's pid so a new server's
# loop is never blocked by a previous server's. An abandoned mutex (loop
# force-killed) is reclaimed.
$mutex = New-Object System.Threading.Mutex($false, "Local\psmux-continuum-autosave-$($server.Id)")
try {
    $haveLock = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $haveLock = $true
}
if (-not $haveLock) {
    exit 0
}

try {
    while ($true) {
        # Block on the server for one interval: returns the instant it exits (reap)
        # or on timeout (time to save). Throws only if the handle goes bad; treat
        # that as the server being gone.
        try {
            if ($server.WaitForExit($cadenceMs)) { break }
        } catch {
            break
        }

        & pwsh -NoProfile -File $saveScript
        Write-Host "psmux-continuum: Auto-saved at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
    }
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
