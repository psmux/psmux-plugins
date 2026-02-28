#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-kanagawa - Kanagawa color theme for psmux (Enhanced)
# =============================================================================
#
# Inspired by the colors of the famous painting by Katsushika Hokusai.
# https://github.com/rebelot/kanagawa.nvim
#
# Options:
#   set -g @kanagawa-variant 'wave'           # wave|dragon|lotus
#   set -g @kanagawa-show-powerline 'on'
#   set -g @kanagawa-separator 'arrow'         # arrow|rounded|slant
#   set -g @kanagawa-show-icons 'on'
#   set -g @kanagawa-show-user 'off'
#   set -g @kanagawa-show-zoom 'on'
#   set -g @kanagawa-show-sync 'on'
#   set -g @kanagawa-show-pane-count 'on'
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

$variant       = Get-Opt '@kanagawa-variant' 'wave'
$showPowerline = Get-Opt '@kanagawa-show-powerline' 'on'
$separator     = Get-Opt '@kanagawa-separator' 'arrow'
$showIcons     = Get-Opt '@kanagawa-show-icons' 'on'
$showUser      = Get-Opt '@kanagawa-show-user' 'off'
$showZoom      = Get-Opt '@kanagawa-show-zoom' 'on'
$showSync      = Get-Opt '@kanagawa-show-sync' 'on'
$showPanes     = Get-Opt '@kanagawa-show-pane-count' 'on'

$palettes = @{
    'wave'   = @{ sumiInk0='#16161D'; sumiInk1='#1F1F28'; sumiInk2='#2A2A37'; sumiInk3='#363646'; sumiInk4='#54546D'; fujiWhite='#DCD7BA'; oldWhite='#C8C093'; fujiGray='#727169'; crystalBlue='#7E9CD8'; springBlue='#7FB4CA'; springGreen='#98BB6C'; surimiOrange='#FFA066'; autumnRed='#C34043'; sakuraPink='#D27E99'; oniViolet='#957FB8'; waveAqua='#6A9589'; roninYellow='#FF9E3B'; carpYellow='#E6C384' }
    'dragon' = @{ sumiInk0='#0D0C0C'; sumiInk1='#12120F'; sumiInk2='#1D1C19'; sumiInk3='#282727'; sumiInk4='#625E5A'; fujiWhite='#C5C9C5'; oldWhite='#A6A69C'; fujiGray='#737C73'; crystalBlue='#658594'; springBlue='#8BA4B0'; springGreen='#87A987'; surimiOrange='#B6927B'; autumnRed='#C4746E'; sakuraPink='#A292A3'; oniViolet='#8992A7'; waveAqua='#8EA4A2'; roninYellow='#FF9E3B'; carpYellow='#E6C384' }
    'lotus'  = @{ sumiInk0='#F2ECBC'; sumiInk1='#E5DDB0'; sumiInk2='#D7D0A4'; sumiInk3='#C9C295'; sumiInk4='#8A8980'; fujiWhite='#43436C'; oldWhite='#545464'; fujiGray='#8A8980'; crystalBlue='#4D699B'; springBlue='#6693BF'; springGreen='#6F894E'; surimiOrange='#CC6D00'; autumnRed='#C84053'; sakuraPink='#B35B79'; oniViolet='#624C83'; waveAqua='#597B75'; roninYellow='#DCA561'; carpYellow='#77713F' }
}

$p = $palettes[$variant]
if (-not $p) { $p = $palettes['wave'] }

switch ($separator) {
    'rounded' { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    'slant'   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    default   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
}
if ($showPowerline -ne 'on') { $sLR=' '; $sRL=' '; $wL=' '; $wR=' '; $wLT=' '; $wRT=' ' }

if ($showIcons -eq 'on') {
    $iSess='󰊠 '; $iWin=' '; $iClock=' '
    $iCal='󰃭 '; $iUser=' '; $iPfx='󰌌 '
} else { $iSess=''; $iWin=''; $iClock=''; $iCal=''; $iUser=''; $iPfx='' }

$zoomInd = if ($showZoom -eq 'on') { "#{?window_zoomed_flag,#[fg=$($p.roninYellow)] 󰁌 ,}" } else { '' }
$syncInd = if ($showSync -eq 'on') { "#{?pane_synchronized,#[fg=$($p.surimiOrange)]#[bg=$($p.sumiInk1)]${sRL}#[bg=$($p.surimiOrange)]#[fg=$($p.sumiInk0),bold] 󰓦 SYNC #[fg=$($p.surimiOrange)]#[bg=$($p.sumiInk1)]${sLR},}" } else { '' }
$paneCount = if ($showPanes -eq 'on') { "#{?#{e|>:#{window_panes}#,1},#[fg=$($p.fujiGray)]  #{window_panes},}" } else { '' }

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$($p.sumiInk1),fg=$($p.fujiWhite)" 2>&1 | Out-Null
& $PSMUX set -g window-status-separator "" 2>&1 | Out-Null

# Status-left: session + optional user
$left = "#[bg=$($p.crystalBlue),fg=$($p.sumiInk0),bold] ${iSess}#S #[fg=$($p.crystalBlue),bg=$($p.sumiInk2)]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$($p.oldWhite),bg=$($p.sumiInk2)] ${iUser}#(whoami) #[fg=$($p.sumiInk2),bg=$($p.sumiInk1)]${sLR} "
} else { $left += "#[fg=$($p.sumiInk2),bg=$($p.sumiInk1)]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# Status-right: prefix + sync + clock + date
$pfx = "#{?client_prefix,#[fg=$($p.roninYellow)]#[bg=$($p.sumiInk1)]${sRL}#[bg=$($p.roninYellow)]#[fg=$($p.sumiInk0),bold] ${iPfx}PREF #[fg=$($p.roninYellow)]#[bg=$($p.sumiInk1)]${sLR},}"
$right = "${pfx}${syncInd}#[fg=$($p.sumiInk3),bg=$($p.sumiInk1)]${sRL}#[fg=$($p.waveAqua),bg=$($p.sumiInk3)] ${iClock}%H:%M #[fg=$($p.sumiInk4),bg=$($p.sumiInk3)]${sRL}#[fg=$($p.springBlue),bg=$($p.sumiInk4)] ${iCal}%a #[fg=$($p.crystalBlue),bg=$($p.sumiInk4)]${sRL}#[fg=$($p.sumiInk0),bg=$($p.crystalBlue),bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# Inactive — thin separators, muted
& $PSMUX set -g window-status-format "#[fg=$($p.sumiInk2),bg=$($p.sumiInk1)]${wLT}#[fg=$($p.fujiGray),bg=$($p.sumiInk2)] ${iWin}#I  #W ${paneCount}#[fg=$($p.sumiInk2),bg=$($p.sumiInk1)]${wRT}" 2>&1 | Out-Null
# Active — full powerline, vibrant
& $PSMUX set -g window-status-current-format "#[fg=$($p.springGreen),bg=$($p.sumiInk1)]${wL}#[fg=$($p.sumiInk0),bg=$($p.springGreen),bold] ${iWin}#I  #W ${zoomInd}${paneCount}#[fg=$($p.springGreen),bg=$($p.sumiInk1)]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-last-style "underscore" 2>&1 | Out-Null
& $PSMUX set -g window-status-activity-style "fg=$($p.surimiOrange),bg=$($p.sumiInk1),bold" 2>&1 | Out-Null
& $PSMUX set -g window-status-bell-style "fg=$($p.autumnRed),bg=$($p.sumiInk1),bold" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($p.crystalBlue)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.sumiInk3)" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$($p.sumiInk2),fg=$($p.fujiWhite)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.sumiInk2),fg=$($p.fujiWhite)" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$($p.oniViolet),fg=$($p.sumiInk0)" 2>&1 | Out-Null

Write-Host "psmux-theme-kanagawa: loaded ($variant, sep=$separator)" -ForegroundColor DarkGray
