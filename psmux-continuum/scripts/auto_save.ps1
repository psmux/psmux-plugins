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
