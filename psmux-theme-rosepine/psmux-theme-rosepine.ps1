#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-rosepine - Rosé Pine color theme for psmux (Enhanced)
# =============================================================================
#
# All natural pine, faux fur and a bit of soho vibes.
# https://rosepinetheme.com
#
# Options:
#   set -g @rosepine-variant 'main'           # main|moon|dawn
#   set -g @rosepine-show-powerline 'on'
#   set -g @rosepine-separator 'arrow'        # arrow|rounded|slant
#   set -g @rosepine-show-icons 'on'
#   set -g @rosepine-show-user 'off'
#   set -g @rosepine-show-zoom 'on'
#   set -g @rosepine-show-sync 'on'
#   set -g @rosepine-show-pane-count 'on'
#   set -g @rosepine-left-icon ''            # custom icon for session
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

$variant       = Get-Opt '@rosepine-variant' 'main'
$showPowerline = Get-Opt '@rosepine-show-powerline' 'on'
$separator     = Get-Opt '@rosepine-separator' 'arrow'
$showIcons     = Get-Opt '@rosepine-show-icons' 'on'
$showUser      = Get-Opt '@rosepine-show-user' 'off'
$showZoom      = Get-Opt '@rosepine-show-zoom' 'on'
$showSync      = Get-Opt '@rosepine-show-sync' 'on'
$showPanes     = Get-Opt '@rosepine-show-pane-count' 'on'
$leftIcon      = Get-Opt '@rosepine-left-icon' ''

$palettes = @{
    'main' = @{ base='#191724'; surface='#1F1D2E'; overlay='#26233A'; muted='#6E6A86'; subtle='#908CAA'; text='#E0DEF4'; love='#EB6F92'; gold='#F6C177'; rose='#EBBCBA'; pine='#31748F'; foam='#9CCFD8'; iris='#C4A7E7' }
    'moon' = @{ base='#232136'; surface='#2A273F'; overlay='#393552'; muted='#6E6A86'; subtle='#908CAA'; text='#E0DEF4'; love='#EB6F92'; gold='#F6C177'; rose='#EA9A97'; pine='#3E8FB0'; foam='#9CCFD8'; iris='#C4A7E7' }
    'dawn' = @{ base='#FAF4ED'; surface='#FFFAF3'; overlay='#F2E9E1'; muted='#9893A5'; subtle='#797593'; text='#575279'; love='#B4637A'; gold='#EA9D34'; rose='#D7827E'; pine='#286983'; foam='#56949F'; iris='#907AA9' }
}

$p = $palettes[$variant]
if (-not $p) { $p = $palettes['main'] }

switch ($separator) {
    'rounded' { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    'slant'   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
    default   { $sLR=''; $sRL=''; $wL=''; $wR=''; $wLT=''; $wRT='' }
}
if ($showPowerline -ne 'on') { $sLR=' '; $sRL=' '; $wL=' '; $wR=' '; $wLT=' '; $wRT=' ' }

if ($showIcons -eq 'on') {
    $iSess="$leftIcon "; $iWin=' '; $iClock=' '
    $iCal='󰃭 '; $iUser=' '; $iPfx='󰌌 '
} else { $iSess=''; $iWin=''; $iClock=''; $iCal=''; $iUser=''; $iPfx='' }

$zoomInd = if ($showZoom -eq 'on') { "#{?window_zoomed_flag,#[fg=$($p.gold)] 󰁌 ,}" } else { '' }
$syncInd = if ($showSync -eq 'on') { "#{?pane_synchronized,#[fg=$($p.love)]#[bg=$($p.base)]${sRL}#[bg=$($p.love)]#[fg=$($p.base),bold] 󰓦 SYNC #[fg=$($p.love)]#[bg=$($p.base)]${sLR},}" } else { '' }
$paneCount = if ($showPanes -eq 'on') { "#{?#{e|>:#{window_panes}#,1},#[fg=$($p.muted)]  #{window_panes},}" } else { '' }

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$($p.base),fg=$($p.text)" 2>&1 | Out-Null
& $PSMUX set -g window-status-separator "" 2>&1 | Out-Null

# Status-left: session with iris accent
$left = "#[bg=$($p.iris),fg=$($p.base),bold] ${iSess}#S #[fg=$($p.iris),bg=$($p.surface)]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$($p.subtle),bg=$($p.surface)] ${iUser}#(whoami) #[fg=$($p.surface),bg=$($p.base)]${sLR} "
} else { $left += "#[fg=$($p.surface),bg=$($p.base)]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# Status-right: prefix + sync + clock + date
$pfx = "#{?client_prefix,#[fg=$($p.love)]#[bg=$($p.base)]${sRL}#[bg=$($p.love)]#[fg=$($p.base),bold] ${iPfx}PREF #[fg=$($p.love)]#[bg=$($p.base)]${sLR},}"
$right = "${pfx}${syncInd}#[fg=$($p.overlay),bg=$($p.base)]${sRL}#[fg=$($p.foam),bg=$($p.overlay)] ${iClock}%H:%M #[fg=$($p.muted),bg=$($p.overlay)]${sRL}#[fg=$($p.rose),bg=$($p.muted)] ${iCal}%a #[fg=$($p.iris),bg=$($p.muted)]${sRL}#[fg=$($p.base),bg=$($p.iris),bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# Inactive — thin separators, muted
& $PSMUX set -g window-status-format "#[fg=$($p.surface),bg=$($p.base)]${wLT}#[fg=$($p.muted),bg=$($p.surface)] ${iWin}#I  #W ${paneCount}#[fg=$($p.surface),bg=$($p.base)]${wRT}" 2>&1 | Out-Null
# Active — full powerline with rose accent
& $PSMUX set -g window-status-current-format "#[fg=$($p.rose),bg=$($p.base)]${wL}#[fg=$($p.base),bg=$($p.rose),bold] ${iWin}#I  #W ${zoomInd}${paneCount}#[fg=$($p.rose),bg=$($p.base)]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-last-style "underscore" 2>&1 | Out-Null
& $PSMUX set -g window-status-activity-style "fg=$($p.gold),bg=$($p.base),bold" 2>&1 | Out-Null
& $PSMUX set -g window-status-bell-style "fg=$($p.love),bg=$($p.base),bold" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($p.iris)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.overlay)" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$($p.surface),fg=$($p.text)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.surface),fg=$($p.text)" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$($p.iris),fg=$($p.base)" 2>&1 | Out-Null

Write-Host "psmux-theme-rosepine: loaded ($variant, sep=$separator)" -ForegroundColor DarkGray
