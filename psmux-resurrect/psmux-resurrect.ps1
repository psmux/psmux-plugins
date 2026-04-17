#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect - Save and restore psmux sessions
# Port of tmux-plugins/tmux-resurrect for psmux
# =============================================================================
#
# Saves and restores the complete psmux environment:
# - All sessions, windows, and pane layouts (exact geometry)
# - Working directories for each pane
# - Active pane per window, active window per session
# - Zoomed pane state
# - Pane titles and running process commands
# - Configurable process restore on recovery
# - Backup rotation (keeps latest 20 saves)
# - Save deduplication (skips if environment unchanged)
#
# Key bindings:
#   Prefix + Ctrl-s  - Save environment
#   Prefix + Ctrl-r  - Restore environment
#
# Options (set in ~/.psmux.conf):
#   set -g @resurrect-dir '~/.psmux/resurrect'
#   set -g @resurrect-capture-pane-contents 'on'
#   set -g @resurrect-processes 'ssh python node'
#   set -g @resurrect-processes 'false'           # disable process restore
#   set -g @resurrect-processes ':all:'           # restore all (dangerous)
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
$DEFAULT_RESURRECT_DIR = Join-Path $env:USERPROFILE '.psmux\resurrect'

# Ensure directories exist
foreach ($d in @($SCRIPTS_DIR, $DEFAULT_RESURRECT_DIR)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# --- Register keybindings (scripts are in scripts/ directory) ---
$savePath = (Join-Path $SCRIPTS_DIR 'save.ps1') -replace '\\', '/'
$restorePath = (Join-Path $SCRIPTS_DIR 'restore.ps1') -replace '\\', '/'

& $script:PSMUX bind-key C-s "run-shell 'pwsh -NoProfile -File \"$savePath\"'" 2>&1 | Out-Null
& $script:PSMUX bind-key C-r "run-shell 'pwsh -NoProfile -File \"$restorePath\"'" 2>&1 | Out-Null

Write-Host "psmux-resurrect: loaded (Prefix+Ctrl-s=save, Prefix+Ctrl-r=restore)" -ForegroundColor DarkGray
