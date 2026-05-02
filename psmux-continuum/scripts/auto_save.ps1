#!/usr/bin/env pwsh
# DO NOT EDIT — regenerated from psmux-continuum.ps1 on plugin load.
# psmux-continuum: Background auto-save loop
param(
    [int]$IntervalMinutes = 15
)

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

# --- Singleton guard: one auto-save loop per user ---
$pidDir  = Join-Path $env:LOCALAPPDATA 'psmux-continuum'
$pidFile = Join-Path $pidDir 'auto_save.pid'
$logFile = Join-Path $pidDir 'auto_save.log'
New-Item -ItemType Directory -Path $pidDir -Force -ErrorAction SilentlyContinue | Out-Null

# Rotate the log if it grew past 256 KB. Add-Content reopens per write, so
# concurrent invocations don't corrupt each other's writes.
if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 262144)) {
    Move-Item $logFile "$logFile.old" -Force -ErrorAction SilentlyContinue
}

function Log {
    param([string]$Message, [string]$Level = 'INF')
    try {
        "[{0}] [{1}] [PID {2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $PID, $Message |
            Add-Content -Path $logFile -Encoding UTF8 -ErrorAction Stop
    }
    catch {}
}

# If a live owner already holds the PID file, defer.
$existingPid = $null
try {
    $existingPid = (Get-Content $pidFile -Raw -ErrorAction Stop).Trim()
}
catch {}
if ($existingPid -match '^\d+$') {
    $existing = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
    if ($existing -and ($existing.ProcessName -in @('pwsh','powershell'))) {
        Log "auto-save already running (PID $existingPid), exiting."
        exit 0
    }
}

# Claim the slot
"$PID" | Set-Content -Path $pidFile -Encoding UTF8 -Force
Log "claimed singleton slot; interval=${IntervalMinutes}m"

$PSMUX = Get-PsmuxBin

# Find the resurrect save script
$saveScript = Join-Path $PSScriptRoot '..\..\psmux-resurrect\scripts\save.ps1'
if (-not (Test-Path $saveScript)) {
    $saveScript = Join-Path $env:USERPROFILE '.psmux\plugins\psmux-resurrect\scripts\save.ps1'
}

if (-not (Test-Path $saveScript)) {
    Log "psmux-resurrect not found. Install it first." 'ERR'
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    exit 1
}

$IntervalSeconds = $IntervalMinutes * 60
$iter = 0

try {
    while ($true) {
        Start-Sleep -Seconds $IntervalSeconds

        # Graceful supersede: if the PID file no longer points to us, exit.
        $owner = $null
        try {
            $owner = (Get-Content $pidFile -Raw -ErrorAction Stop).Trim()
        }
        catch {}
        if ($owner -ne "$PID") {
            Log "superseded, exiting."
            break
        }

        # Check if psmux server is still running
        $sessions = & $PSMUX ls 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Log "psmux server not running, stopping auto-save." 'WRN'
            break
        }

        # Run the save; capture all streams (output, errors, warnings) into the log.
        & pwsh -NoProfile -File $saveScript *>> $logFile
        Log "auto-saved."

        # Bound memory growth in this long-running loop
        $iter++
        if (($iter % 4) -eq 0) {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            [GC]::Collect()
        }
    }
}
finally {
    Log "exiting; releasing singleton slot."
    # Release singleton slot only if we still own it
    try {
        $owner = (Get-Content $pidFile -Raw -ErrorAction Stop).Trim()
        if ($owner -eq "$PID") {
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}
}
