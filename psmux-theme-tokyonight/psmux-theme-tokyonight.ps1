#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-tokyonight - Tokyo Night color theme for psmux (Enhanced)
# =============================================================================
#
# A clean dark theme that celebrates the lights of downtown Tokyo at night.
# https://github.com/folke/tokyonight.nvim
#
# Options:
#   set -g @tokyonight-style 'night'          # night|storm|moon
#   set -g @tokyonight-show-powerline 'on'
#   set -g @tokyonight-separator 'arrow'       # arrow|rounded|slant
#   set -g @tokyonight-show-icons 'on'
#   set -g @tokyonight-show-user 'on'
#   set -g @tokyonight-show-zoom 'on'
#   set -g @tokyonight-show-sync 'on'
#   set -g @tokyonight-show-pane-count 'on'
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

$style         = Get-Opt '@tokyonight-style' 'night'
$showPowerline = Get-Opt '@tokyonight-show-powerline' 'on'
$separator     = Get-Opt '@tokyonight-separator' 'arrow'
$showIcons     = Get-Opt '@tokyonight-show-icons' 'on'
$showUser      = Get-Opt '@tokyonight-show-user' 'on'
$showZoom      = Get-Opt '@tokyonight-show-zoom' 'on'
$showSync      = Get-Opt '@tokyonight-show-sync' 'on'
$showPanes     = Get-Opt '@tokyonight-show-pane-count' 'on'

$palettes = @{
    'night' = @{ bg='#1A1B26'; bg1='#24283B'; bg2='#292E42'; bg3='#3B4261'; fg='#C0CAF5'; fg_dark='#A9B1D6'; fg_gutter='#3B4261'; comment='#565F89'; blue='#7AA2F7'; cyan='#7DCFFF'; green='#9ECE6A'; magenta='#BB9AF7'; orange='#FF9E64'; red='#F7768E'; teal='#1ABC9C'; yellow='#E0AF68'; purple='#9D7CD8' }
    'storm' = @{ bg='#24283B'; bg1='#1F2335'; bg2='#292E42'; bg3='#3B4261'; fg='#C0CAF5'; fg_dark='#A9B1D6'; fg_gutter='#3B4261'; comment='#565F89'; blue='#7AA2F7'; cyan='#7DCFFF'; green='#9ECE6A'; magenta='#BB9AF7'; orange='#FF9E64'; red='#F7768E'; teal='#1ABC9C'; yellow='#E0AF68'; purple='#9D7CD8' }
    'moon'  = @{ bg='#222436'; bg1='#1E2030'; bg2='#2F334D'; bg3='#444A73'; fg='#C8D3F5'; fg_dark='#B4C2F0'; fg_gutter='#444A73'; comment='#636DA6'; blue='#82AAFF'; cyan='#86E1FC'; green='#C3E88D'; magenta='#FCA7EA'; orange='#FF966C'; red='#FF757F'; teal='#4FD6BE'; yellow='#FFC777'; purple='#C099FF' }
}

$p = $palettes[$style]
if (-not $p) { $p = $palettes['night'] }

switch ($separator) {
    'rounded' { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    'slant'   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    default   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
}
if ($showPowerline -ne 'on') { $sLR=' '; $sRL=' '; $wL=' '; $wR=' '; $wLT=' '; $wRT=' ' }

if ($showIcons -eq 'on') {
    $iSess='󰒲 '; $iWin=' '; $iClock=' '
    $iCal='󰃭 '; $iUser=' '; $iPfx='󰌌 '
} else { $iSess=''; $iWin=''; $iClock=''; $iCal=''; $iUser=''; $iPfx='' }

$zoomInd = if ($showZoom -eq 'on') { "#{?window_zoomed_flag,#[fg=$($p.yellow)] 󰁌 ,}" } else { '' }
$syncInd = if ($showSync -eq 'on') { "#{?pane_synchronized,#[fg=$($p.orange)]#[bg=$($p.bg)]${sRL}#[bg=$($p.orange)]#[fg=$($p.bg),bold] 󰓦 SYNC #[fg=$($p.orange)]#[bg=$($p.bg)]${sLR},}" } else { '' }
$paneCount = if ($showPanes -eq 'on') { "#{?#{e|>:#{window_panes}#,1},#[fg=$($p.comment)]  #{window_panes},}" } else { '' }

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$($p.bg),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g window-status-separator "" 2>&1 | Out-Null

# Status-left: session in blue
$left = "#[bg=$($p.blue),fg=$($p.bg),bold] ${iSess}#S #[fg=$($p.blue),bg=$($p.bg1)]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$($p.fg_dark),bg=$($p.bg1)] ${iUser}#(whoami) #[fg=$($p.bg1),bg=$($p.bg)]${sLR} "
} else { $left += "#[fg=$($p.bg1),bg=$($p.bg)]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# Status-right: prefix + sync + clock + date
$pfx = "#{?client_prefix,#[fg=$($p.orange)]#[bg=$($p.bg)]${sRL}#[bg=$($p.orange)]#[fg=$($p.bg),bold] ${iPfx}PREF #[fg=$($p.orange)]#[bg=$($p.bg)]${sLR},}"
$right = "${pfx}${syncInd}#[fg=$($p.bg2),bg=$($p.bg)]${sRL}#[fg=$($p.teal),bg=$($p.bg2)] ${iClock}%H:%M #[fg=$($p.bg3),bg=$($p.bg2)]${sRL}#[fg=$($p.cyan),bg=$($p.bg3)] ${iCal}%a #[fg=$($p.blue),bg=$($p.bg3)]${sRL}#[fg=$($p.bg),bg=$($p.blue),bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# Inactive — thin separators
& $PSMUX set -g window-status-format "#[fg=$($p.bg1),bg=$($p.bg)]${wLT}#[fg=$($p.comment),bg=$($p.bg1)] ${iWin}#I  #W ${paneCount}#[fg=$($p.bg1),bg=$($p.bg)]${wRT}" 2>&1 | Out-Null
# Active — full powerline with magenta accent
& $PSMUX set -g window-status-current-format "#[fg=$($p.magenta),bg=$($p.bg)]${wL}#[fg=$($p.bg),bg=$($p.magenta),bold] ${iWin}#I  #W ${zoomInd}${paneCount}#[fg=$($p.magenta),bg=$($p.bg)]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-last-style "underscore" 2>&1 | Out-Null
& $PSMUX set -g window-status-activity-style "fg=$($p.orange),bg=$($p.bg),bold" 2>&1 | Out-Null
& $PSMUX set -g window-status-bell-style "fg=$($p.red),bg=$($p.bg),bold" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($p.blue)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.bg3)" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$($p.bg1),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.bg1),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$($p.purple),fg=$($p.bg)" 2>&1 | Out-Null

Write-Host "psmux-theme-tokyonight: loaded ($style, sep=$separator)" -ForegroundColor DarkGray
