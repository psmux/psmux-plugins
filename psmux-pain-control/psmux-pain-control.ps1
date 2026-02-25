#!/usr/bin/env pwsh
# =============================================================================
# psmux-pain-control - Better pane navigation and management for psmux
# Port of tmux-plugins/tmux-pain-control for psmux
# =============================================================================
#
# Provides intuitive keybindings for pane navigation, resizing, and splitting.
# All bindings use the prefix key.
#
# Options:
#   set -g @pane_resize '5'    # resize step (default: 5)
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

# --- Configuration ---
$resizeStep = 5
$resizeOpt = (& $PSMUX show-options -g -v '@pane_resize' 2>&1 | Out-String).Trim()
if ($resizeOpt -match '^\d+$') { $resizeStep = [int]$resizeOpt }

# =============================================================================
# PANE NAVIGATION (vim-style: h/j/k/l)
# =============================================================================
& $PSMUX bind-key h select-pane -L 2>&1 | Out-Null   # Left
& $PSMUX bind-key j select-pane -D 2>&1 | Out-Null   # Down
& $PSMUX bind-key k select-pane -U 2>&1 | Out-Null   # Up
& $PSMUX bind-key l select-pane -R 2>&1 | Out-Null   # Right

# =============================================================================
# PANE RESIZING (Alt + vim keys)
# NOTE: psmux treats key bindings case-insensitively (H == h), so we use
# Alt+h/j/k/l instead of Shift (H/J/K/L) for resize to avoid conflicts.
# =============================================================================
& $PSMUX bind-key -r M-h resize-pane -L $resizeStep 2>&1 | Out-Null
& $PSMUX bind-key -r M-j resize-pane -D $resizeStep 2>&1 | Out-Null
& $PSMUX bind-key -r M-k resize-pane -U $resizeStep 2>&1 | Out-Null
& $PSMUX bind-key -r M-l resize-pane -R $resizeStep 2>&1 | Out-Null

# =============================================================================
# PANE SPLITTING (intuitive chars)
# =============================================================================
# | and \ for horizontal split (side by side)
& $PSMUX bind-key '|' split-window -h -c '#{pane_current_path}' 2>&1 | Out-Null
& $PSMUX bind-key '\' split-window -h -c '#{pane_current_path}' 2>&1 | Out-Null

# - and _ for vertical split (top/bottom)
& $PSMUX bind-key '-' split-window -v -c '#{pane_current_path}' 2>&1 | Out-Null
& $PSMUX bind-key '_' split-window -v -c '#{pane_current_path}' 2>&1 | Out-Null

# =============================================================================
# WINDOW NAVIGATION
# =============================================================================
# < and > to swap windows left/right
& $PSMUX bind-key -r '<' swap-window -t -1 2>&1 | Out-Null
& $PSMUX bind-key -r '>' swap-window -t +1 2>&1 | Out-Null

# =============================================================================
# NEW WINDOWS/PANES IN CURRENT DIRECTORY
# =============================================================================
& $PSMUX bind-key c new-window -c '#{pane_current_path}' 2>&1 | Out-Null

Write-Host "psmux-pain-control: loaded" -ForegroundColor DarkGray
