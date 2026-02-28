#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-rosepine - Rosé Pine color theme for psmux
# Port of rose-pine/tmux for psmux
# =============================================================================
#
# All natural pine, faux fur and a bit of soho vibes for the classy minimalist.
# https://rosepinetheme.com
#
# Variants: main (default), moon, dawn (light)
#
# Options:
#   set -g @rosepine-variant 'main'          # main|moon|dawn
#   set -g @rosepine-show-powerline 'on'     # powerline arrows
#   set -g @rosepine-separator 'arrow'       # arrow|rounded|slant
#   set -g @rosepine-show-icons 'on'         # nerd font icons
#   set -g @rosepine-left-icon 'session'     # session|window|rocket
#   set -g @rosepine-show-user 'on'          # show username in left
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
$leftIcon      = Get-Opt '@rosepine-left-icon' 'session'
$showUser      = Get-Opt '@rosepine-show-user' 'on'

# --- Color palettes by variant ---
$palettes = @{
    main = @{
        base='#191724'; surface='#1f1d2e'; overlay='#26233a'
        muted='#6e6a86'; subtle='#908caa'; text='#e0def4'
        love='#eb6f92'; gold='#f6c177'; rose='#ebbcba'
        pine='#31748f'; foam='#9ccfd8'; iris='#c4a7e7'
        hl_low='#21202e'; hl_med='#403d52'; hl_high='#524f67'
    }
    moon = @{
        base='#232136'; surface='#2a273f'; overlay='#393552'
        muted='#6e6a86'; subtle='#908caa'; text='#e0def4'
        love='#eb6f92'; gold='#f6c177'; rose='#ea9a97'
        pine='#3e8fb0'; foam='#9ccfd8'; iris='#c4a7e7'
        hl_low='#2a283e'; hl_med='#44415a'; hl_high='#56526e'
    }
    dawn = @{
        base='#faf4ed'; surface='#fffaf3'; overlay='#f2e9e1'
        muted='#9893a5'; subtle='#797593'; text='#575279'
        love='#b4637a'; gold='#ea9d34'; rose='#d7827e'
        pine='#286983'; foam='#56949f'; iris='#907aa9'
        hl_low='#f4ede8'; hl_med='#dfdad9'; hl_high='#cecacd'
    }
}

$p = $palettes[$variant]
if (-not $p) { $p = $palettes['main'] }

# --- Separators ---
switch ($separator) {
    'rounded' {
        $sLR = ''; $sRL = ''  # right-pointing / left-pointing rounded
        $wL = ''; $wR = ''
    }
    'slant' {
        $sLR = ''; $sRL = ''
        $wL = ''; $wR = ''
    }
    default {  # arrow
        $sLR = ''; $sRL = ''
        $wL = ''; $wR = ''
    }
}

if ($showPowerline -ne 'on') {
    $sLR = ' '; $sRL = ' '; $wL = ' '; $wR = ' '
}

# --- Icons ---
if ($showIcons -eq 'on') {
    $iSession = ' '
    $iWindow  = ' '
    $iRocket  = ' '
    $iClock   = ' '
    $iCal     = ' '
    $iUser    = ' '
} else {
    $iSession = ''; $iWindow = ''; $iRocket = ''
    $iClock = ''; $iCal = ''; $iUser = ''
}

# Left icon
switch ($leftIcon) {
    'window'  { $leftGlyph = $iWindow }
    'rocket'  { $leftGlyph = $iRocket }
    default   { $leftGlyph = $iSession }
}

# =============================================================================
# APPLY THEME
# =============================================================================

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$($p.base),fg=$($p.text)" 2>&1 | Out-Null

# --- Status left: icon + session + optional user ---
$leftStr = "#[bg=$($p.iris),fg=$($p.base),bold] ${leftGlyph}#S "
$leftStr += "#[fg=$($p.iris),bg=$($p.overlay)]${sLR}"

if ($showUser -eq 'on') {
    $leftStr += "#[fg=$($p.subtle),bg=$($p.overlay)] ${iUser}#(whoami) "
    $leftStr += "#[fg=$($p.overlay),bg=$($p.base)]${sLR} "
} else {
    $leftStr += "#[fg=$($p.overlay),bg=$($p.base)]${sLR} "
}

& $PSMUX set -g status-left $leftStr 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# --- Status right: prefix + time + date segments ---
$prefixInd = "#{?client_prefix,#[fg=$($p.love)]#[bg=$($p.base)]${sRL}#[bg=$($p.love)]#[fg=$($p.base),bold]  PREF #[fg=$($p.love)]#[bg=$($p.base)]${sLR},}"

$rightStr = "${prefixInd}"
$rightStr += "#[fg=$($p.overlay),bg=$($p.base)]${sRL}"
$rightStr += "#[fg=$($p.foam),bg=$($p.overlay)] ${iClock}%H:%M "
$rightStr += "#[fg=$($p.hl_med),bg=$($p.overlay)]${sRL}"
$rightStr += "#[fg=$($p.gold),bg=$($p.hl_med)] ${iCal}%a "
$rightStr += "#[fg=$($p.pine),bg=$($p.hl_med)]${sRL}"
$rightStr += "#[fg=$($p.text),bg=$($p.pine),bold] ${iCal}%d-%b "

& $PSMUX set -g status-right $rightStr 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# --- Window tabs ---
# Inactive: pill-shaped with muted colors
& $PSMUX set -g window-status-format "#[fg=$($p.overlay),bg=$($p.base)]${wL}#[fg=$($p.muted),bg=$($p.overlay)] ${iWindow}#I  #W #[fg=$($p.overlay),bg=$($p.base)]${wR}" 2>&1 | Out-Null

# Active: rose-colored pill with bold
& $PSMUX set -g window-status-current-format "#[fg=$($p.rose),bg=$($p.base)]${wL}#[fg=$($p.base),bg=$($p.rose),bold] ${iWindow}#I  #W #[fg=$($p.rose),bg=$($p.base)]${wR}" 2>&1 | Out-Null

# Activity
& $PSMUX set -g window-status-activity-style "fg=$($p.gold),bg=$($p.base)" 2>&1 | Out-Null

# Pane borders
& $PSMUX set -g pane-active-border-style "fg=$($p.iris)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.overlay)" 2>&1 | Out-Null

# Messages
& $PSMUX set -g message-style "bg=$($p.overlay),fg=$($p.text)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.overlay),fg=$($p.text)" 2>&1 | Out-Null

# Copy mode
& $PSMUX set -g mode-style "bg=$($p.iris),fg=$($p.base)" 2>&1 | Out-Null

Write-Host "psmux-theme-rosepine: loaded ($variant, sep=$separator)" -ForegroundColor DarkGray
