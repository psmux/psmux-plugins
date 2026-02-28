#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-onedark - One Dark color theme for psmux (Enhanced)
# =============================================================================
#
# Inspired by Atom's One Dark syntax theme.
# https://github.com/joshdick/onedark.vim
#
# Options:
#   set -g @onedark-show-powerline 'on'
#   set -g @onedark-separator 'arrow'         # arrow|rounded|slant
#   set -g @onedark-show-icons 'on'
#   set -g @onedark-show-user 'on'
#   set -g @onedark-show-zoom 'on'
#   set -g @onedark-show-sync 'on'
#   set -g @onedark-show-pane-count 'on'
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

$showPowerline = Get-Opt '@onedark-show-powerline' 'on'
$separator     = Get-Opt '@onedark-separator' 'arrow'
$showIcons     = Get-Opt '@onedark-show-icons' 'on'
$showUser      = Get-Opt '@onedark-show-user' 'on'
$showZoom      = Get-Opt '@onedark-show-zoom' 'on'
$showSync      = Get-Opt '@onedark-show-sync' 'on'
$showPanes     = Get-Opt '@onedark-show-pane-count' 'on'

# Atom One Dark palette
$black    = '#282C34'
$bg1      = '#31353F'
$bg2      = '#393F4A'
$gutter   = '#4B5263'
$comment  = '#5C6370'
$fg       = '#ABB2BF'
$white    = '#C8CCD4'
$red      = '#E06C75'
$green    = '#98C379'
$yellow   = '#E5C07B'
$blue     = '#61AFEF'
$magenta  = '#C678DD'
$cyan     = '#56B6C2'
$orange   = '#D19A66'

switch ($separator) {
    'rounded' { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    'slant'   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    default   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
}
if ($showPowerline -ne 'on') { $sLR=' '; $sRL=' '; $wL=' '; $wR=' '; $wLT=' '; $wRT=' ' }

if ($showIcons -eq 'on') {
    $iSess=' '; $iWin=' '; $iClock=' '
    $iCal='󰃭 '; $iUser=' '; $iPfx='󰌌 '
} else { $iSess=''; $iWin=''; $iClock=''; $iCal=''; $iUser=''; $iPfx='' }

$zoomInd = if ($showZoom -eq 'on') { "#{?window_zoomed_flag,#[fg=${yellow}] 󰁌 ,}" } else { '' }
$syncInd = if ($showSync -eq 'on') { "#{?pane_synchronized,#[fg=${orange}]#[bg=${black}]${sRL}#[bg=${orange}]#[fg=${black},bold] 󰓦 SYNC #[fg=${orange}]#[bg=${black}]${sLR},}" } else { '' }
$paneCount = if ($showPanes -eq 'on') { "#{?#{e|>:#{window_panes}#,1},#[fg=${comment}]  #{window_panes},}" } else { '' }

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=${black},fg=${fg}" 2>&1 | Out-Null
& $PSMUX set -g window-status-separator "" 2>&1 | Out-Null

# Status-left: session in blue
$left = "#[bg=${blue},fg=${black},bold] ${iSess}#S #[fg=${blue},bg=${bg1}]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=${fg},bg=${bg1}] ${iUser}#(whoami) #[fg=${bg1},bg=${black}]${sLR} "
} else { $left += "#[fg=${bg1},bg=${black}]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# Status-right: prefix + sync + clock + date
$pfx = "#{?client_prefix,#[fg=${orange}]#[bg=${black}]${sRL}#[bg=${orange}]#[fg=${black},bold] ${iPfx}PREF #[fg=${orange}]#[bg=${black}]${sLR},}"
$right = "${pfx}${syncInd}#[fg=${bg2},bg=${black}]${sRL}#[fg=${cyan},bg=${bg2}] ${iClock}%H:%M #[fg=${gutter},bg=${bg2}]${sRL}#[fg=${green},bg=${gutter}] ${iCal}%a #[fg=${blue},bg=${gutter}]${sRL}#[fg=${black},bg=${blue},bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# Inactive — thin separators
& $PSMUX set -g window-status-format "#[fg=${bg1},bg=${black}]${wLT}#[fg=${comment},bg=${bg1}] ${iWin}#I  #W ${paneCount}#[fg=${bg1},bg=${black}]${wRT}" 2>&1 | Out-Null
# Active — full powerline with green accent
& $PSMUX set -g window-status-current-format "#[fg=${green},bg=${black}]${wL}#[fg=${black},bg=${green},bold] ${iWin}#I  #W ${zoomInd}${paneCount}#[fg=${green},bg=${black}]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-last-style "underscore" 2>&1 | Out-Null
& $PSMUX set -g window-status-activity-style "fg=${orange},bg=${black},bold" 2>&1 | Out-Null
& $PSMUX set -g window-status-bell-style "fg=${red},bg=${black},bold" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=${blue}" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=${bg2}" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=${bg1},fg=${fg}" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=${bg1},fg=${fg}" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=${blue},fg=${black}" 2>&1 | Out-Null

Write-Host "psmux-theme-onedark: loaded (sep=$separator)" -ForegroundColor DarkGray
