#!/usr/bin/env pwsh
# Capture visible pane content to file
$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin
$LOG_DIR = Join-Path $env:USERPROFILE '.psmux\logs'
if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

$sessionName = (& $PSMUX display-message -p '#{session_name}' 2>&1 | Out-String).Trim()
$windowIndex = (& $PSMUX display-message -p '#{window_index}' 2>&1 | Out-String).Trim()
$paneIndex = (& $PSMUX display-message -p '#{pane_index}' 2>&1 | Out-String).Trim()
$timestamp = Get-Date -Format 'yyyyMMddTHHmmss'

$captureFile = Join-Path $LOG_DIR "psmux-screen-${sessionName}-w${windowIndex}-p${paneIndex}-${timestamp}.log"

# Capture visible pane content
& $PSMUX capture-pane -J 2>&1 | Out-Null
$content = & $PSMUX show-buffer 2>&1 | Out-String
$content | Set-Content -Path $captureFile -Encoding UTF8 -Force

& $PSMUX display-message "Screen captured: $captureFile" 2>&1 | Out-Null
