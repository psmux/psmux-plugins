#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-gruvbox - Gruvbox color theme for psmux (Enhanced)
# =============================================================================
#
# Retro groove color scheme designed for readability.
# https://github.com/morhetz/gruvbox
#
# Options:
#   set -g @gruvbox-variant 'dark'           # dark|light
#   set -g @gruvbox-contrast 'medium'        # soft|medium|hard
#   set -g @gruvbox-show-powerline 'on'
#   set -g @gruvbox-separator 'arrow'        # arrow|rounded|slant
#   set -g @gruvbox-show-icons 'on'
#   set -g @gruvbox-show-user 'on'
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

$variant       = Get-Opt '@gruvbox-variant' 'dark'
$contrast      = Get-Opt '@gruvbox-contrast' 'medium'
$showPowerline = Get-Opt '@gruvbox-show-powerline' 'on'
$separator     = Get-Opt '@gruvbox-separator' 'arrow'
$showIcons     = Get-Opt '@gruvbox-show-icons' 'on'
$showUser      = Get-Opt '@gruvbox-show-user' 'on'

$palettes = @{
    'dark-soft'   = @{ bg0='#32302f'; bg1='#3c3836'; bg2='#504945'; bg3='#665c54'; bg4='#7c6f64'; fg='#ebdbb2'; fg2='#d5c4a1'; gray='#928374'; red='#fb4934'; green='#b8bb26'; yellow='#fabd2f'; blue='#83a598'; purple='#d3869b'; aqua='#8ec07c'; orange='#fe8019' }
    'dark-medium' = @{ bg0='#282828'; bg1='#3c3836'; bg2='#504945'; bg3='#665c54'; bg4='#7c6f64'; fg='#ebdbb2'; fg2='#d5c4a1'; gray='#928374'; red='#fb4934'; green='#b8bb26'; yellow='#fabd2f'; blue='#83a598'; purple='#d3869b'; aqua='#8ec07c'; orange='#fe8019' }
    'dark-hard'   = @{ bg0='#1d2021'; bg1='#3c3836'; bg2='#504945'; bg3='#665c54'; bg4='#7c6f64'; fg='#ebdbb2'; fg2='#d5c4a1'; gray='#928374'; red='#fb4934'; green='#b8bb26'; yellow='#fabd2f'; blue='#83a598'; purple='#d3869b'; aqua='#8ec07c'; orange='#fe8019' }
    'light-soft'  = @{ bg0='#f2e5bc'; bg1='#ebdbb2'; bg2='#d5c4a1'; bg3='#bdae93'; bg4='#a89984'; fg='#3c3836'; fg2='#504945'; gray='#928374'; red='#9d0006'; green='#79740e'; yellow='#b57614'; blue='#076678'; purple='#8f3f71'; aqua='#427b58'; orange='#af3a03' }
    'light-medium'= @{ bg0='#fbf1c7'; bg1='#ebdbb2'; bg2='#d5c4a1'; bg3='#bdae93'; bg4='#a89984'; fg='#3c3836'; fg2='#504945'; gray='#928374'; red='#9d0006'; green='#79740e'; yellow='#b57614'; blue='#076678'; purple='#8f3f71'; aqua='#427b58'; orange='#af3a03' }
    'light-hard'  = @{ bg0='#f9f5d7'; bg1='#ebdbb2'; bg2='#d5c4a1'; bg3='#bdae93'; bg4='#a89984'; fg='#3c3836'; fg2='#504945'; gray='#928374'; red='#9d0006'; green='#79740e'; yellow='#b57614'; blue='#076678'; purple='#8f3f71'; aqua='#427b58'; orange='#af3a03' }
}

$key = "$variant-$contrast"
$p = $palettes[$key]
if (-not $p) { $p = $palettes['dark-medium'] }

switch ($separator) {
    'rounded' { $sLR=''; $sRL=''; $wL=''; $wR='' }
    'slant'   { $sLR=''; $sRL=''; $wL=''; $wR='' }
    default   { $sLR=''; $sRL=''; $wL=''; $wR='' }
}
if ($showPowerline -ne 'on') { $sLR=' '; $sRL=' '; $wL=' '; $wR=' ' }

if ($showIcons -eq 'on') {
    $iSess=' '; $iWin=' '; $iClock=' '
    $iCal='󰃭 '; $iUser=' '; $iPfx='󰌌 '
} else { $iSess=''; $iWin=''; $iClock=''; $iCal=''; $iUser=''; $iPfx='' }

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$($p.bg0),fg=$($p.fg)" 2>&1 | Out-Null

$left = "#[bg=$($p.yellow),fg=$($p.bg0),bold] ${iSess}#S #[fg=$($p.yellow),bg=$($p.bg1)]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$($p.fg2),bg=$($p.bg1)] ${iUser}#(whoami) #[fg=$($p.bg1),bg=$($p.bg0)]${sLR} "
} else { $left += "#[fg=$($p.bg1),bg=$($p.bg0)]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

$pfx = "#{?client_prefix,#[fg=$($p.orange)]#[bg=$($p.bg0)]${sRL}#[bg=$($p.orange)]#[fg=$($p.bg0),bold] ${iPfx}PREF #[fg=$($p.orange)]#[bg=$($p.bg0)]${sLR},}"
$right = "${pfx}#[fg=$($p.bg2),bg=$($p.bg0)]${sRL}#[fg=$($p.aqua),bg=$($p.bg2)] ${iClock}%H:%M #[fg=$($p.bg3),bg=$($p.bg2)]${sRL}#[fg=$($p.blue),bg=$($p.bg3)] ${iCal}%a #[fg=$($p.yellow),bg=$($p.bg3)]${sRL}#[fg=$($p.bg0),bg=$($p.yellow),bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

& $PSMUX set -g window-status-format "#[fg=$($p.bg1),bg=$($p.bg0)]${wL}#[fg=$($p.gray),bg=$($p.bg1)] ${iWin}#I  #W #[fg=$($p.bg1),bg=$($p.bg0)]${wR}" 2>&1 | Out-Null
& $PSMUX set -g window-status-current-format "#[fg=$($p.green),bg=$($p.bg0)]${wL}#[fg=$($p.bg0),bg=$($p.green),bold] ${iWin}#I  #W #[fg=$($p.green),bg=$($p.bg0)]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-activity-style "fg=$($p.orange),bg=$($p.bg0)" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($p.aqua)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.bg1)" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$($p.bg1),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.bg1),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$($p.yellow),fg=$($p.bg0)" 2>&1 | Out-Null

Write-Host "psmux-theme-gruvbox: loaded ($variant-$contrast, sep=$separator)" -ForegroundColor DarkGray
