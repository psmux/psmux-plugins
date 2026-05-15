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
# NOTE: The auto_save loop is a per-user singleton enforced by a PID file
# at $env:LOCALAPPDATA\psmux-continuum\auto_save.pid. This means the
# client-attached hook in plugin.conf can re-fire on every re-attach
# without accumulating long-running pwsh processes — duplicate launches
# detect the live owner and exit immediately.
$autoSaveScript = @'
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
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'auto_save.ps1') -Value $autoSaveScript -Force

# --- Create the auto-restore script ---
$autoRestoreScript = @'
#!/usr/bin/env pwsh
# DO NOT EDIT — regenerated from psmux-continuum.ps1 on plugin load.
# psmux-continuum: Auto-restore on server start
$ErrorActionPreference = 'Continue'

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
# DO NOT EDIT — regenerated from psmux-continuum.ps1 on plugin load.
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

# --- Start auto-save background loop ---
$interval = 15  # Default 15 minutes

# Try to read interval from psmux options
$intervalOpt = (& $script:PSMUX show-options -g -v '@continuum-save-interval' 2>&1 | Out-String).Trim()
if ($intervalOpt -match '^\d+$') {
    $interval = [int]$intervalOpt
}

if ($interval -gt 0) {
    $autoSavePath = Join-Path $SCRIPTS_DIR 'auto_save.ps1'
    # Detached, hidden pwsh — single process, not a Start-Job wrapper.
    # The singleton guard inside auto_save.ps1 makes repeated launches safe.
    Start-Process -FilePath 'pwsh' `
        -ArgumentList @('-NoProfile','-File',$autoSavePath,'-IntervalMinutes',"$interval") `
        -WindowStyle Hidden | Out-Null
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
