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
