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
