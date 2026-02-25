#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-nord - Nord color theme for psmux
# Port of arcticicestudio/nord-tmux for psmux
# =============================================================================
#
# An arctic, north-bluish clean and elegant theme.
# https://nordtheme.com
#
# Palette (Polar Night → Snow Storm → Frost → Aurora):
#   nord0:  #2e3440   nord1:  #3b4252   nord2:  #434c5e   nord3:  #4c566a
#   nord4:  #d8dee9   nord5:  #e5e9f0   nord6:  #eceff4
#   nord7:  #8fbcbb   nord8:  #88c0d0   nord9:  #81a1c1   nord10: #5e81ac
#   nord11: #bf616a   nord12: #d08770   nord13: #ebcb8b   nord14: #a3be8c
#   nord15: #b48ead
#
# Options:
#   set -g @nord-show-powerline 'on'
#   set -g @nord-powerline-style 'arrow'  # arrow|round
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

$showPowerline = Get-Opt '@nord-show-powerline' 'on'
$plStyle = Get-Opt '@nord-powerline-style' 'arrow'

# --- Nord colors ---
$nord0  = '#2e3440'   # Polar Night (darkest)
$nord1  = '#3b4252'
$nord2  = '#434c5e'
$nord3  = '#4c566a'   # Polar Night (lightest)
$nord4  = '#d8dee9'   # Snow Storm
$nord5  = '#e5e9f0'
$nord6  = '#eceff4'   # Snow Storm (brightest)
$nord7  = '#8fbcbb'   # Frost (teal)
$nord8  = '#88c0d0'   # Frost (light blue)
$nord9  = '#81a1c1'   # Frost (blue)
$nord10 = '#5e81ac'   # Frost (dark blue)
$nord11 = '#bf616a'   # Aurora (red)
$nord12 = '#d08770'   # Aurora (orange)
$nord13 = '#ebcb8b'   # Aurora (yellow)
$nord14 = '#a3be8c'   # Aurora (green)
$nord15 = '#b48ead'   # Aurora (purple)

# --- Separators ---
if ($showPowerline -eq 'on') {
    if ($plStyle -eq 'round') {
        $lSep = ''; $rSep = ''
    } else {
        $lSep = ''; $rSep = ''
    }
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
& $PSMUX set -g status-style "bg=$nord1,fg=$nord4" 2>&1 | Out-Null

# Status left: session name on frost blue
& $PSMUX set -g status-left "#[bg=$nord9,fg=$nord0,bold] #S #[fg=$nord9,bg=$nord1]${lSep} " 2>&1 | Out-Null
& $PSMUX set -g status-left-length 25 2>&1 | Out-Null

# Status right
$prefixInd = "#{?client_prefix,#[fg=$nord13]#[bg=$nord1]${rSep}#[bg=$nord13]#[fg=$nord0] WAIT #[fg=$nord13]#[bg=$nord1]${lSep},}"
& $PSMUX set -g status-right "${prefixInd}#[fg=$nord3,bg=$nord1]${rSep}#[fg=$nord4,bg=$nord3] %H:%M #[fg=$nord10,bg=$nord3]${rSep}#[fg=$nord6,bg=$nord10,bold] %d-%b " 2>&1 | Out-Null
& $PSMUX set -g status-right-length 60 2>&1 | Out-Null

# Window status (inactive)
& $PSMUX set -g window-status-format "#[fg=$nord3,bg=$nord1]${lSep}#[fg=$nord4,bg=$nord3] #I:#W #{?window_flags,#{window_flags},}#[fg=$nord3,bg=$nord1]${lSep}" 2>&1 | Out-Null

# Window status (current/active) - frost highlight
& $PSMUX set -g window-status-current-format "#[fg=$nord8,bg=$nord1]${lSep}#[fg=$nord0,bg=$nord8,bold] #I:#W #{?window_flags,#{window_flags},}#[fg=$nord8,bg=$nord1]${lSep}" 2>&1 | Out-Null

# Activity
& $PSMUX set -g window-status-activity-style "fg=$nord13,bg=$nord1" 2>&1 | Out-Null

# Pane borders
& $PSMUX set -g pane-active-border-style "fg=$nord8" 2>&1 | Out-Null

# Messages
& $PSMUX set -g message-style "bg=$nord2,fg=$nord4" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$nord2,fg=$nord4" 2>&1 | Out-Null

# Copy mode
& $PSMUX set -g mode-style "bg=$nord9,fg=$nord0" 2>&1 | Out-Null

Write-Host "psmux-theme-nord: loaded" -ForegroundColor DarkGray
