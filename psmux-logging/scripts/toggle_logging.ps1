#!/usr/bin/env pwsh
# Toggle pane logging on/off
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

# Get current pane info
$sessionName = (& $PSMUX display-message -p '#{session_name}' 2>&1 | Out-String).Trim()
$windowIndex = (& $PSMUX display-message -p '#{window_index}' 2>&1 | Out-String).Trim()
$paneIndex = (& $PSMUX display-message -p '#{pane_index}' 2>&1 | Out-String).Trim()
$timestamp = Get-Date -Format 'yyyyMMddTHHmmss'

$logFile = Join-Path $LOG_DIR "psmux-${sessionName}-w${windowIndex}-p${paneIndex}-${timestamp}.log"

# Check if pipe-pane is already active (toggle off)
$currentPipe = (& $PSMUX show-options -g -v '@logging_active' 2>&1 | Out-String).Trim()

if ($currentPipe -eq 'on') {
    # Stop logging
    & $PSMUX pipe-pane 2>&1 | Out-Null   # Empty pipe-pane stops piping
    & $PSMUX set -g @logging_active 'off' 2>&1 | Out-Null
    & $PSMUX display-message "Logging stopped" 2>&1 | Out-Null
} else {
    # Start logging via pipe-pane
    & $PSMUX pipe-pane -o "pwsh -NoProfile -Command { `$input | Out-File -Append -FilePath '$logFile' -Encoding UTF8 }" 2>&1 | Out-Null
    & $PSMUX set -g @logging_active 'on' 2>&1 | Out-Null
    & $PSMUX set -g @logging_file "$logFile" 2>&1 | Out-Null
    & $PSMUX display-message "Logging to: $logFile" 2>&1 | Out-Null
}
