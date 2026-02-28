#!/usr/bin/env pwsh
# =============================================================================
# psmux-logging - Log pane output to files
# Port of tmux-plugins/tmux-logging for psmux
# =============================================================================
#
# Record pane output to log files. Useful for debugging, auditing, or
# capturing terminal sessions.
#
# Key bindings:
#   Prefix + Alt-o   - Toggle logging for current pane
#   Prefix + Alt-p   - Save visible pane content ("screenshot")
#   Prefix + Alt-i   - Save complete pane history
#   Prefix + Alt-c   - Clear pane history
#
# Options:
#   set -g @logging-path '~/.psmux/logs'
#   set -g @logging-filename 'psmux-#{session_name}-#{window_index}-#{pane_index}-%Y%m%dT%H%M%S.log'
#   set -g @screen-capture-filename 'psmux-screen-#{session_name}-#{window_index}-#{pane_index}-%Y%m%dT%H%M%S.log'
# =============================================================================

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin
$SCRIPTS_DIR = Join-Path $PSScriptRoot 'scripts'
$DEFAULT_LOG_DIR = Join-Path $env:USERPROFILE '.psmux\logs'

foreach ($d in @($SCRIPTS_DIR, $DEFAULT_LOG_DIR)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# --- Toggle logging script ---
$toggleScript = @'
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
    & $PSMUX set -g '@logging_active' 'off' 2>&1 | Out-Null
    & $PSMUX display-message "Logging stopped" 2>&1 | Out-Null
} else {
    # Start logging via pipe-pane
    & $PSMUX pipe-pane -o "pwsh -NoProfile -Command { `$input | Out-File -Append -FilePath '$logFile' -Encoding UTF8 }" 2>&1 | Out-Null
    & $PSMUX set -g '@logging_active' 'on' 2>&1 | Out-Null
    & $PSMUX set -g '@logging_file' "$logFile" 2>&1 | Out-Null
    & $PSMUX display-message "Logging to: $logFile" 2>&1 | Out-Null
}
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'toggle_logging.ps1') -Value $toggleScript -Force

# --- Screen capture script ---
$captureScript = @'
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
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'capture_screen.ps1') -Value $captureScript -Force

# --- Full history capture script ---
$historyScript = @'
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
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'capture_history.ps1') -Value $historyScript -Force

# --- Register keybindings ---
$togglePath = (Join-Path $SCRIPTS_DIR 'toggle_logging.ps1') -replace '\\', '/'
$capturePath = (Join-Path $SCRIPTS_DIR 'capture_screen.ps1') -replace '\\', '/'
$historyPath = (Join-Path $SCRIPTS_DIR 'capture_history.ps1') -replace '\\', '/'

# --- Register keybindings ---
# NOTE: psmux treats key bindings case-insensitively, so we use distinct keys.
# NOTE: Paths already use forward slashes (from -replace above).
# Key mapping:  Alt+o = toggle lOgging, Alt+p = screenshoT, Alt+i = full hIstory
& $PSMUX bind-key M-o "run-shell 'pwsh -NoProfile -File \"$togglePath\"'" 2>&1 | Out-Null
& $PSMUX bind-key M-p "run-shell 'pwsh -NoProfile -File \"$capturePath\"'" 2>&1 | Out-Null
& $PSMUX bind-key M-i "run-shell 'pwsh -NoProfile -File \"$historyPath\"'" 2>&1 | Out-Null
& $PSMUX bind-key M-c clear-history 2>&1 | Out-Null

Write-Host "psmux-logging: loaded (Prefix+Alt-o=toggle, Prefix+Alt-p=screenshot, Prefix+Alt-i=history)" -ForegroundColor DarkGray
