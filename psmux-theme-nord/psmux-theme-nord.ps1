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
#   set -g @nord-separator 'arrow'            # arrow|rounded|slant
#   set -g @nord-show-icons 'on'
#   set -g @nord-show-user 'on'
#   set -g @nord-show-zoom 'on'
#   set -g @nord-show-sync 'on'
#   set -g @nord-show-pane-count 'on'
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
$showZoom      = Get-Opt '@nord-show-zoom' 'on'
$showSync      = Get-Opt '@nord-show-sync' 'on'
$showPanes     = Get-Opt '@nord-show-pane-count' 'on'

# Nord palette
$n0  = '#2E3440'    # Polar Night 0
$n1  = '#3B4252'    # Polar Night 1
$n2  = '#434C5E'    # Polar Night 2
$n3  = '#4C566A'    # Polar Night 3
$n4  = '#D8DEE9'    # Snow Storm 0
$n5  = '#E5E9F0'    # Snow Storm 1
$n6  = '#ECEFF4'    # Snow Storm 2
$n7  = '#8FBCBB'    # Frost - frozen water
$n8  = '#88C0D0'    # Frost - clear ice
$n9  = '#81A1C1'    # Frost - arctic ocean
$n10 = '#5E81AC'    # Frost - deep arctic
$n11 = '#BF616A'    # Aurora - red
$n12 = '#D08770'    # Aurora - orange
$n13 = '#EBCB8B'    # Aurora - yellow
$n14 = '#A3BE8C'    # Aurora - green
$n15 = '#B48EAD'    # Aurora - purple

switch ($separator) {
    'rounded' { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    'slant'   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    default   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
}
if ($showPowerline -ne 'on') { $sLR=' '; $sRL=' '; $wL=' '; $wR=' '; $wLT=' '; $wRT=' ' }

if ($showIcons -eq 'on') {
    $iSess=' '; $iWin=' '; $iClock=' '
    $iCal='󰃶 '; $iUser=' '; $iPfx='󰌌 '
} else { $iSess=''; $iWin=''; $iClock=''; $iCal=''; $iUser=''; $iPfx='' }

$zoomInd = if ($showZoom -eq 'on') { "#{?window_zoomed_flag,#[fg=${n13}] 󰁌 ,}" } else { '' }
$syncInd = if ($showSync -eq 'on') { "#{?pane_synchronized,#[fg=${n12}]#[bg=${n0}]${sRL}#[bg=${n12}]#[fg=${n0},bold] 󰓦 SYNC #[fg=${n12}]#[bg=${n0}]${sLR},}" } else { '' }
$paneCount = if ($showPanes -eq 'on') { "#{?#{e|>:#{window_panes}#,1},#[fg=${n3}]  #{window_panes},}" } else { '' }

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=${n0},fg=${n4}" 2>&1 | Out-Null
& $PSMUX set -g window-status-separator "" 2>&1 | Out-Null

# Status-left: session accent in frost blue
$left = "#[bg=${n10},fg=${n6},bold] ${iSess}#S #[fg=${n10},bg=${n1}]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=${n4},bg=${n1}] ${iUser}#(whoami) #[fg=${n1},bg=${n0}]${sLR} "
} else { $left += "#[fg=${n1},bg=${n0}]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# Status-right: prefix + sync + clock + date
$pfx = "#{?client_prefix,#[fg=${n12}]#[bg=${n0}]${sRL}#[bg=${n12}]#[fg=${n0},bold] ${iPfx}PREF #[fg=${n12}]#[bg=${n0}]${sLR},}"
$right = "${pfx}${syncInd}#[fg=${n2},bg=${n0}]${sRL}#[fg=${n7},bg=${n2}] ${iClock}%H:%M #[fg=${n3},bg=${n2}]${sRL}#[fg=${n8},bg=${n3}] ${iCal}%a #[fg=${n10},bg=${n3}]${sRL}#[fg=${n6},bg=${n10},bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# Inactive — thin separators
& $PSMUX set -g window-status-format "#[fg=${n1},bg=${n0}]${wLT}#[fg=${n3},bg=${n1}] ${iWin}#I  #W ${paneCount}#[fg=${n1},bg=${n0}]${wRT}" 2>&1 | Out-Null
# Active — full powerline with aurora green
& $PSMUX set -g window-status-current-format "#[fg=${n9},bg=${n0}]${wL}#[fg=${n0},bg=${n9},bold] ${iWin}#I  #W ${zoomInd}${paneCount}#[fg=${n9},bg=${n0}]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-last-style "underscore" 2>&1 | Out-Null
& $PSMUX set -g window-status-activity-style "fg=${n12},bg=${n0},bold" 2>&1 | Out-Null
& $PSMUX set -g window-status-bell-style "fg=${n11},bg=${n0},bold" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=${n8}" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=${n1}" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=${n1},fg=${n4}" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=${n1},fg=${n4}" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=${n9},fg=${n0}" 2>&1 | Out-Null

Write-Host "psmux-theme-nord: loaded (sep=$separator)" -ForegroundColor DarkGray
