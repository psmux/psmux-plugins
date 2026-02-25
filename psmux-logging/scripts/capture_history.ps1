#!/usr/bin/env pwsh
# Capture complete pane history to file
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

$histFile = Join-Path $LOG_DIR "psmux-history-${sessionName}-w${windowIndex}-p${paneIndex}-${timestamp}.log"

# Capture full history
& $PSMUX capture-pane -S - -E - -J 2>&1 | Out-Null
$content = & $PSMUX show-buffer 2>&1 | Out-String
$content | Set-Content -Path $histFile -Encoding UTF8 -Force

& $PSMUX display-message "History saved: $histFile" 2>&1 | Out-Null
