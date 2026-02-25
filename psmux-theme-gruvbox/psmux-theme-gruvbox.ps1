#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-gruvbox - Gruvbox color theme for psmux
# Port of egel/tmux-gruvbox for psmux
# =============================================================================
#
# A retro groove color scheme with warm, earthy tones.
# https://github.com/morhetz/gruvbox
#
# Palette (dark/hard):
#   bg:    #1d2021   bg0:   #282828   bg1: #3c3836   bg2: #504945
#   fg:    #ebdbb2   fg1:   #fbf1c7
#   red:   #fb4934   green: #b8bb26   yellow: #fabd2f
#   blue:  #83a598   purple:#d3869b   aqua:   #8ec07c
#   orange:#fe8019   gray:  #928374
#
# Options:
#   set -g @gruvbox-variant 'dark'         # dark|light
#   set -g @gruvbox-contrast 'medium'      # soft|medium|hard
#   set -g @gruvbox-show-powerline 'on'
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

$variant = Get-Opt '@gruvbox-variant' 'dark'
$contrast = Get-Opt '@gruvbox-contrast' 'medium'
$showPowerline = Get-Opt '@gruvbox-show-powerline' 'on'

# --- Color palettes ---
$darkBg = switch ($contrast) {
    'soft'   { '#32302f' }
    'hard'   { '#1d2021' }
    default  { '#282828' }
}

if ($variant -eq 'dark') {
    $bg     = $darkBg
    $bg1    = '#3c3836'; $bg2 = '#504945'; $bg3 = '#665c54'; $bg4 = '#7c6f64'
    $fg     = '#ebdbb2'; $fg1 = '#fbf1c7'
    $red    = '#fb4934'; $green = '#b8bb26'; $yellow = '#fabd2f'
    $blue   = '#83a598'; $purple = '#d3869b'; $aqua = '#8ec07c'
    $orange = '#fe8019'; $gray = '#928374'
} else {
    $bg     = '#fbf1c7'
    $bg1    = '#ebdbb2'; $bg2 = '#d5c4a1'; $bg3 = '#bdae93'; $bg4 = '#a89984'
    $fg     = '#3c3836'; $fg1 = '#282828'
    $red    = '#9d0006'; $green = '#79740e'; $yellow = '#b57614'
    $blue   = '#076678'; $purple = '#8f3f71'; $aqua = '#427b58'
    $orange = '#af3a03'; $gray = '#928374'
}

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
& $PSMUX set -g status-style "bg=$bg1,fg=$fg" 2>&1 | Out-Null

# Status left
& $PSMUX set -g status-left "#[bg=$yellow,fg=$bg,bold] #S #[fg=$yellow,bg=$bg1]${lSep} " 2>&1 | Out-Null
& $PSMUX set -g status-left-length 25 2>&1 | Out-Null

# Status right
$prefixInd = "#{?client_prefix,#[fg=$orange]#[bg=$bg1]${rSep}#[bg=$orange]#[fg=$bg] WAIT #[fg=$orange]#[bg=$bg1]${lSep},}"
& $PSMUX set -g status-right "${prefixInd}#[fg=$bg2,bg=$bg1]${rSep}#[fg=$fg,bg=$bg2] %H:%M #[fg=$aqua,bg=$bg2]${rSep}#[fg=$bg,bg=$aqua,bold] %d-%b " 2>&1 | Out-Null
& $PSMUX set -g status-right-length 60 2>&1 | Out-Null

# Window status (inactive)
& $PSMUX set -g window-status-format "#[fg=$bg2,bg=$bg1]${lSep}#[fg=$fg,bg=$bg2] #I:#W #{?window_flags,#{window_flags},}#[fg=$bg2,bg=$bg1]${lSep}" 2>&1 | Out-Null

# Window status (current/active) - highlighted with green
& $PSMUX set -g window-status-current-format "#[fg=$green,bg=$bg1]${lSep}#[fg=$bg,bg=$green,bold] #I:#W #{?window_flags,#{window_flags},}#[fg=$green,bg=$bg1]${lSep}" 2>&1 | Out-Null

# Activity
& $PSMUX set -g window-status-activity-style "fg=$orange,bg=$bg1" 2>&1 | Out-Null

# Pane borders
& $PSMUX set -g pane-active-border-style "fg=$aqua" 2>&1 | Out-Null

# Messages
& $PSMUX set -g message-style "bg=$bg2,fg=$fg" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$bg2,fg=$fg" 2>&1 | Out-Null

# Copy mode
& $PSMUX set -g mode-style "bg=$yellow,fg=$bg" 2>&1 | Out-Null

Write-Host "psmux-theme-gruvbox: loaded ($variant/$contrast)" -ForegroundColor DarkGray
