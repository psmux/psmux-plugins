#!/usr/bin/env pwsh
# =============================================================================
# psmux-continuum - Auto-save and auto-restore for psmux
# Port of tmux-plugins/tmux-continuum for psmux
# =============================================================================
#
# Automatically saves psmux environment at configurable intervals.
# Optionally restores environment when psmux server starts.
# Requires psmux-resurrect.
#
# Options (set in ~/.psmux.conf):
#   set -g @continuum-save-interval '15'    # minutes (0 to disable)
#   set -g @continuum-restore 'on'          # auto-restore on server start
#   set -g @continuum-boot 'on'             # auto-start psmux on system boot
# =============================================================================

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$script:PSMUX = Get-PsmuxBin
$SCRIPTS_DIR = Join-Path $PSScriptRoot 'scripts'
$RESURRECT_SCRIPTS = Join-Path (Split-Path -Parent $PSScriptRoot) 'psmux-resurrect\scripts'

if (-not (Test-Path $SCRIPTS_DIR)) {
    New-Item -ItemType Directory -Path $SCRIPTS_DIR -Force | Out-Null
}

# --- Create the auto-save background script ---
$autoSaveScript = @'
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
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'auto_save.ps1') -Value $autoSaveScript -Force

# --- Create the auto-restore script ---
$autoRestoreScript = @'
#!/usr/bin/env pwsh
# psmux-continuum: Auto-restore on server start
$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

# Opt-in via @continuum-restore 'on'. The plugin.conf hook is registered
# unconditionally; this script is the option gate, evaluated at exec time.
$PSMUX = Get-PsmuxBin
$restoreOpt = (& $PSMUX show-options -gv '@continuum-restore' 2>&1 | Out-String).Trim()
if ($restoreOpt -ne 'on') { exit 0 }

# Fire at most once per psmux server lifetime. The hook is on session-created
# and restore.ps1 itself calls new-session for each saved session, so without
# this guard the hook would re-enter for every restored session.
$firedOpt = (& $PSMUX show-options -gv '@continuum-restore-fired' 2>&1 | Out-String).Trim()
if ($firedOpt -eq 'on') { exit 0 }
& $PSMUX set-option -g '@continuum-restore-fired' 'on' 2>&1 | Out-Null

$restoreScript = Join-Path $PSScriptRoot '..\..\psmux-resurrect\scripts\restore.ps1'
if (-not (Test-Path $restoreScript)) {
    $restoreScript = Join-Path $env:USERPROFILE '.psmux\plugins\psmux-resurrect\scripts\restore.ps1'
}

$resurrectDir = Join-Path $env:USERPROFILE '.psmux\resurrect'
$lastFile = Join-Path $resurrectDir 'last'

if ((Test-Path $restoreScript) -and (Test-Path $lastFile)) {
    & pwsh -NoProfile -File $restoreScript
}
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'auto_restore.ps1') -Value $autoRestoreScript -Force

# --- Create boot script ---
$bootScript = @'
#!/usr/bin/env pwsh
# psmux-continuum: Register/unregister psmux auto-start on Windows login
param(
    [switch]$Enable,
    [switch]$Disable
)

$taskName = 'PsmuxAutoStart'

if ($Disable) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "psmux-continuum: Auto-start disabled" -ForegroundColor Yellow
    return
}

if ($Enable) {
    # Find psmux binary
    $psmuxPath = (Get-Command psmux -ErrorAction SilentlyContinue).Source
    if (-not $psmuxPath) {
        $psmuxPath = (Get-Command pmux -ErrorAction SilentlyContinue).Source
    }
    if (-not $psmuxPath) {
        Write-Host "psmux not found in PATH" -ForegroundColor Red
        return
    }

    $action = New-ScheduledTaskAction -Execute $psmuxPath -Argument "new-session -d -s main"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "psmux-continuum: Auto-start enabled (at login)" -ForegroundColor Green
}
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'boot.ps1') -Value $bootScript -Force

# --- Start auto-save background job ---
$interval = 15  # Default 15 minutes

# Try to read interval from psmux options
$intervalOpt = (& $script:PSMUX show-options -g -v '@continuum-save-interval' 2>&1 | Out-String).Trim()
if ($intervalOpt -match '^\d+$') {
    $interval = [int]$intervalOpt
}

if ($interval -gt 0) {
    $autoSavePath = Join-Path $SCRIPTS_DIR 'auto_save.ps1'
    Start-Job -ScriptBlock {
        param($script, $interval)
        & pwsh -NoProfile -File $script -IntervalMinutes $interval
    } -ArgumentList $autoSavePath, $interval | Out-Null
}

# --- Auto-restore on first load ---
$restoreOpt = (& $script:PSMUX show-options -g -v '@continuum-restore' 2>&1 | Out-String).Trim()
if ($restoreOpt -eq 'on') {
    $autoRestorePath = Join-Path $SCRIPTS_DIR 'auto_restore.ps1'
    & pwsh -NoProfile -File $autoRestorePath
}

# --- Boot setup ---
$bootOpt = (& $script:PSMUX show-options -g -v '@continuum-boot' 2>&1 | Out-String).Trim()
if ($bootOpt -eq 'on') {
    $bootPath = Join-Path $SCRIPTS_DIR 'boot.ps1'
    & pwsh -NoProfile -File $bootPath -Enable
}

Write-Host "psmux-continuum: loaded (auto-save every ${interval}m)" -ForegroundColor DarkGray
