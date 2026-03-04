#!/usr/bin/env pwsh
# =============================================================================
# psmux-sensible - Sensible default settings for psmux
# Port of tmux-plugins/tmux-sensible for psmux
# =============================================================================
#
# Provides a set of sane defaults that everyone can agree on.
# Inspired by vim-sensible.
#
# Options set here use -o (only-if-unset) so they never override explicit
# user settings from ~/.psmux.conf.
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

# --- Sensible defaults (all use -go so user overrides are respected) ---

# Reduce escape-time for faster key recognition (tmux-sensible uses 0, but
# 50ms is safer on Windows to avoid swallowing escape sequences)
& $PSMUX set -go escape-time 50 2>&1 | Out-Null

# Increase scrollback buffer
& $PSMUX set -go history-limit 50000 2>&1 | Out-Null

# Enable mouse support (most users expect this)
& $PSMUX set -go mouse on 2>&1 | Out-Null

# Use vi mode keys (more powerful in copy mode)
& $PSMUX set -go mode-keys vi 2>&1 | Out-Null

# Enable focus events (useful for vim/neovim focus detection)
& $PSMUX set -go focus-events on 2>&1 | Out-Null

# Display messages longer so you can actually read them
& $PSMUX set -go display-time 2000 2>&1 | Out-Null

# Display pane numbers longer
& $PSMUX set -go display-panes-time 2000 2>&1 | Out-Null

# Refresh status bar more frequently
& $PSMUX set -go status-interval 5 2>&1 | Out-Null

# Start window numbering at 1 (matches keyboard layout)
& $PSMUX set -go base-index 1 2>&1 | Out-Null

# Start pane numbering at 1
& $PSMUX set -go pane-base-index 1 2>&1 | Out-Null

# Renumber windows when one is closed
& $PSMUX set -go renumber-windows on 2>&1 | Out-Null

# Automatically rename windows based on running command
& $PSMUX set -go automatic-rename on 2>&1 | Out-Null

# --- Keybinding improvements ---

# Prefix + R to reload config
& $PSMUX bind-key R "source-file ~/.psmux.conf; display-message 'Config reloaded!'" 2>&1 | Out-Null

# Better split bindings (keep the defaults too)
& $PSMUX bind-key '|' split-window -h 2>&1 | Out-Null
& $PSMUX bind-key '-' split-window -v 2>&1 | Out-Null

# Navigate windows with Shift+Arrow (no prefix needed)
& $PSMUX bind-key -n S-Left previous-window 2>&1 | Out-Null
& $PSMUX bind-key -n S-Right next-window 2>&1 | Out-Null

Write-Host "psmux-sensible: loaded" -ForegroundColor DarkGray
