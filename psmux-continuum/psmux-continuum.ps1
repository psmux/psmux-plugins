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

while ($true) {
    Start-Sleep -Seconds $IntervalSeconds

    # Check if psmux server is still running
    $sessions = & $PSMUX ls 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host "psmux-continuum: Server not running, stopping auto-save." -ForegroundColor Yellow
        break
    }

    # Run the save
    & pwsh -NoProfile -File $saveScript
    Write-Host "psmux-continuum: Auto-saved at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
}
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'auto_save.ps1') -Value $autoSaveScript -Force

# --- Create the auto-restore script ---
$autoRestoreScript = @'
#!/usr/bin/env pwsh
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
