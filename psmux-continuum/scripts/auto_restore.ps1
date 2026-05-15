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
