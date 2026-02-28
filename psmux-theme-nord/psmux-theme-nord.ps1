#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-nord - Nord color theme for psmux (Enhanced)
# =============================================================================
#
# An arctic, north-bluish clean and elegant theme.
# https://www.nordtheme.com
#
# Options:
#   set -g @nord-show-powerline 'on'
#   set -g @nord-separator 'arrow'          # arrow|rounded|slant
#   set -g @nord-show-icons 'on'
#   set -g @nord-show-user 'on'
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
$separator     = Get-Opt '@nord-separator' 'arrow'
$showIcons     = Get-Opt '@nord-show-icons' 'on'
$showUser      = Get-Opt '@nord-show-user' 'on'

# Nord palette
$n0='#2e3440'; $n1='#3b4252'; $n2='#434c5e'; $n3='#4c566a'
$n4='#d8dee9'; $n5='#e5e9f0'; $n6='#eceff4'
$n7='#8fbcbb'; $n8='#88c0d0'; $n9='#81a1c1'; $n10='#5e81ac'
$n11='#bf616a'; $n12='#d08770'; $n13='#ebcb8b'; $n14='#a3be8c'; $n15='#b48ead'

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
& $PSMUX set -g status-style "bg=$n1,fg=$n4" 2>&1 | Out-Null

$left = "#[bg=$n9,fg=$n0,bold] ${iSess}#S #[fg=$n9,bg=$n2]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$n4,bg=$n2] ${iUser}#(whoami) #[fg=$n2,bg=$n1]${sLR} "
} else { $left += "#[fg=$n2,bg=$n1]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

$pfx = "#{?client_prefix,#[fg=$n13]#[bg=$n1]${sRL}#[bg=$n13]#[fg=$n0,bold] ${iPfx}WAIT #[fg=$n13]#[bg=$n1]${sLR},}"
$right = "${pfx}#[fg=$n3,bg=$n1]${sRL}#[fg=$n7,bg=$n3] ${iClock}%H:%M #[fg=$n2,bg=$n3]${sRL}#[fg=$n13,bg=$n2] ${iCal}%a #[fg=$n10,bg=$n2]${sRL}#[fg=$n6,bg=$n10,bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

& $PSMUX set -g window-status-format "#[fg=$n3,bg=$n1]${wL}#[fg=$n4,bg=$n3] ${iWin}#I  #W #[fg=$n3,bg=$n1]${wR}" 2>&1 | Out-Null
& $PSMUX set -g window-status-current-format "#[fg=$n8,bg=$n1]${wL}#[fg=$n0,bg=$n8,bold] ${iWin}#I  #W #[fg=$n8,bg=$n1]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-activity-style "fg=$n13,bg=$n1" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$n8" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$n2" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$n2,fg=$n4" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$n2,fg=$n4" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$n9,fg=$n0" 2>&1 | Out-Null

Write-Host "psmux-theme-nord: loaded (sep=$separator)" -ForegroundColor DarkGray
