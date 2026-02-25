#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-tokyonight - Tokyo Night color theme for psmux
# Port of janoamaral/tokyo-night-tmux for psmux
# =============================================================================
#
# A clean dark theme inspired by the Tokyo Night VS Code theme.
# https://github.com/folke/tokyonight.nvim
#
# Palette:
#   bg:      #1a1b26   bg_dark: #16161e   fg:    #c0caf5
#   blue:    #7aa2f7   cyan:    #7dcfff   green: #9ece6a
#   magenta: #bb9af7   red:     #f7768e   yellow: #e0af68
#   orange:  #ff9e64   teal:    #1abc9c   comment: #565f89
#
# Options:
#   set -g @tokyonight-style 'night'  # night|storm|moon
#   set -g @tokyonight-show-powerline 'on'
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

function Get-Opt {
    param([string]$Name, [string]$Default)
    $v = (& $PSMUX show-options -g -v $Name 2>&1 | Out-String).Trim()
    if ($v -and $v -notmatch 'unknown|error|invalid|^$') { return $v }
    return $Default
}

$style = Get-Opt '@tokyonight-style' 'night'
$showPowerline = Get-Opt '@tokyonight-show-powerline' 'on'

# --- Color palettes by style ---
$styles = @{
    night = @{
        bg      = '#1a1b26'; bg_dark = '#16161e'; bg_hl   = '#292e42'
        fg      = '#c0caf5'; fg_dark = '#a9b1d6'; comment = '#565f89'
        blue    = '#7aa2f7'; cyan    = '#7dcfff'; green   = '#9ece6a'
        magenta = '#bb9af7'; red     = '#f7768e'; yellow  = '#e0af68'
        orange  = '#ff9e64'; teal    = '#1abc9c'
    }
    storm = @{
        bg      = '#24283b'; bg_dark = '#1f2335'; bg_hl   = '#292e42'
        fg      = '#c0caf5'; fg_dark = '#a9b1d6'; comment = '#565f89'
        blue    = '#7aa2f7'; cyan    = '#7dcfff'; green   = '#9ece6a'
        magenta = '#bb9af7'; red     = '#f7768e'; yellow  = '#e0af68'
        orange  = '#ff9e64'; teal    = '#1abc9c'
    }
    moon = @{
        bg      = '#222436'; bg_dark = '#1e2030'; bg_hl   = '#2f334d'
        fg      = '#c8d3f5'; fg_dark = '#b4c2f0'; comment = '#636da6'
        blue    = '#82aaff'; cyan    = '#86e1fc'; green   = '#c3e88d'
        magenta = '#c099ff'; red     = '#ff757f'; yellow  = '#ffc777'
        orange  = '#ff966c'; teal    = '#4fd6be'
    }
}

$c = $styles[$style]
if (-not $c) { $c = $styles['night'] }

# --- Separators ---
if ($showPowerline -eq 'on') {
    $lSep = ''; $rSep = ''
} else {
    $lSep = ''; $rSep = ''
}

# =============================================================================
# APPLY THEME
# =============================================================================

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$($c.bg),fg=$($c.fg)" 2>&1 | Out-Null

# Status left
& $PSMUX set -g status-left "#[bg=$($c.blue),fg=$($c.bg_dark),bold]  #S #[fg=$($c.blue),bg=$($c.bg)]${lSep} " 2>&1 | Out-Null
& $PSMUX set -g status-left-length 30 2>&1 | Out-Null

# Status right
$prefixInd = "#{?client_prefix,#[fg=$($c.orange)]#[bg=$($c.bg)]${rSep}#[bg=$($c.orange)]#[fg=$($c.bg_dark)]  #[fg=$($c.orange)]#[bg=$($c.bg)]${lSep},}"
& $PSMUX set -g status-right "${prefixInd}#[fg=$($c.bg_hl),bg=$($c.bg)]${rSep}#[fg=$($c.fg),bg=$($c.bg_hl)]  %H:%M #[fg=$($c.magenta),bg=$($c.bg_hl)]${rSep}#[fg=$($c.bg_dark),bg=$($c.magenta),bold]  %d-%b " 2>&1 | Out-Null
& $PSMUX set -g status-right-length 60 2>&1 | Out-Null

# Window status (inactive)
& $PSMUX set -g window-status-format "#[fg=$($c.bg_hl),bg=$($c.bg)]${lSep}#[fg=$($c.comment),bg=$($c.bg_hl)] #I #W #{?window_flags,#{window_flags},}#[fg=$($c.bg_hl),bg=$($c.bg)]${lSep}" 2>&1 | Out-Null

# Window status (current/active)
& $PSMUX set -g window-status-current-format "#[fg=$($c.cyan),bg=$($c.bg)]${lSep}#[fg=$($c.bg_dark),bg=$($c.cyan),bold] #I #W #{?window_flags,#{window_flags},}#[fg=$($c.cyan),bg=$($c.bg)]${lSep}" 2>&1 | Out-Null

# Activity
& $PSMUX set -g window-status-activity-style "fg=$($c.yellow),bg=$($c.bg)" 2>&1 | Out-Null

# Pane borders
& $PSMUX set -g pane-active-border-style "fg=$($c.blue)" 2>&1 | Out-Null

# Messages
& $PSMUX set -g message-style "bg=$($c.bg_hl),fg=$($c.fg)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($c.bg_hl),fg=$($c.fg)" 2>&1 | Out-Null

# Copy mode
& $PSMUX set -g mode-style "bg=$($c.blue),fg=$($c.bg_dark)" 2>&1 | Out-Null

Write-Host "psmux-theme-tokyonight: loaded ($style)" -ForegroundColor DarkGray
