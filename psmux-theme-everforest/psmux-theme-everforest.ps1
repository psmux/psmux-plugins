#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-everforest - Everforest color theme for psmux
# =============================================================================
#
# Comfortable & Pleasant Color Scheme for long-term use.
# Inspired by nature — green tones that are easy on the eyes.
# https://github.com/sainnhe/everforest
#
# Variants: dark (default), light
# Contrast: soft, medium (default), hard
#
# Options:
#   set -g @everforest-variant 'dark'         # dark|light
#   set -g @everforest-contrast 'medium'      # soft|medium|hard
#   set -g @everforest-show-powerline 'on'
#   set -g @everforest-separator 'arrow'      # arrow|rounded|slant
#   set -g @everforest-show-icons 'on'
#   set -g @everforest-show-user 'on'
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

$variant       = Get-Opt '@everforest-variant' 'dark'
$contrast      = Get-Opt '@everforest-contrast' 'medium'
$showPowerline = Get-Opt '@everforest-show-powerline' 'on'
$separator     = Get-Opt '@everforest-separator' 'arrow'
$showIcons     = Get-Opt '@everforest-show-icons' 'on'
$showUser      = Get-Opt '@everforest-show-user' 'on'

# --- Palettes ---
$palettes = @{
    'dark-soft' = @{
        bg0='#333c43'; bg1='#3a464c'; bg2='#434f55'; bg3='#4d5960'
        fg='#d3c6aa'; gray='#7a8478'; gray2='#9da9a0'
        red='#e67e80'; orange='#e69875'; yellow='#dbbc7f'
        green='#a7c080'; aqua='#83c092'; blue='#7fbbb3'; purple='#d699b6'
    }
    'dark-medium' = @{
        bg0='#2d353b'; bg1='#343f44'; bg2='#3d484d'; bg3='#475258'
        fg='#d3c6aa'; gray='#7a8478'; gray2='#9da9a0'
        red='#e67e80'; orange='#e69875'; yellow='#dbbc7f'
        green='#a7c080'; aqua='#83c092'; blue='#7fbbb3'; purple='#d699b6'
    }
    'dark-hard' = @{
        bg0='#272e33'; bg1='#2e383c'; bg2='#374145'; bg3='#414b50'
        fg='#d3c6aa'; gray='#7a8478'; gray2='#9da9a0'
        red='#e67e80'; orange='#e69875'; yellow='#dbbc7f'
        green='#a7c080'; aqua='#83c092'; blue='#7fbbb3'; purple='#d699b6'
    }
    'light-soft' = @{
        bg0='#f3ead3'; bg1='#eae4ca'; bg2='#e1ddc4'; bg3='#d8d3ba'
        fg='#5c6a72'; gray='#939f91'; gray2='#829181'
        red='#f85552'; orange='#f57d26'; yellow='#dfa000'
        green='#8da101'; aqua='#35a77c'; blue='#3a94c5'; purple='#df69ba'
    }
    'light-medium' = @{
        bg0='#fdf6e3'; bg1='#f4f0d9'; bg2='#efebd4'; bg3='#e6e2cc'
        fg='#5c6a72'; gray='#939f91'; gray2='#829181'
        red='#f85552'; orange='#f57d26'; yellow='#dfa000'
        green='#8da101'; aqua='#35a77c'; blue='#3a94c5'; purple='#df69ba'
    }
    'light-hard' = @{
        bg0='#fffbef'; bg1='#f8f4e8'; bg2='#f2eee2'; bg3='#e9e5d9'
        fg='#5c6a72'; gray='#939f91'; gray2='#829181'
        red='#f85552'; orange='#f57d26'; yellow='#dfa000'
        green='#8da101'; aqua='#35a77c'; blue='#3a94c5'; purple='#df69ba'
    }
}

$key = "$variant-$contrast"
$p = $palettes[$key]
if (-not $p) { $p = $palettes['dark-medium'] }

# --- Separators ---
switch ($separator) {
    'rounded' { $sLR = ''; $sRL = ''; $wL = ''; $wR = '' }
    'slant'   { $sLR = ''; $sRL = ''; $wL = ''; $wR = '' }
    default   { $sLR = ''; $sRL = ''; $wL = ''; $wR = '' }
}

if ($showPowerline -ne 'on') {
    $sLR = ' '; $sRL = ' '; $wL = ' '; $wR = ' '
}

# --- Icons ---
if ($showIcons -eq 'on') {
    $iSess = '󰔱 '; $iWin = ' '; $iClock = ' '
    $iCal = '󰃭 '; $iUser = ' '; $iPrefix = '󰌌 '
} else {
    $iSess = ''; $iWin = ''; $iClock = ''
    $iCal = ''; $iUser = ''; $iPrefix = ''
}

# =============================================================================
# APPLY THEME
# =============================================================================

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$($p.bg0),fg=$($p.fg)" 2>&1 | Out-Null

# --- Status left ---
$left = "#[bg=$($p.green),fg=$($p.bg0),bold] ${iSess}#S "
$left += "#[fg=$($p.green),bg=$($p.bg1)]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$($p.gray2),bg=$($p.bg1)] ${iUser}#(whoami) "
    $left += "#[fg=$($p.bg1),bg=$($p.bg0)]${sLR} "
} else {
    $left += "#[fg=$($p.bg1),bg=$($p.bg0)]${sLR} "
}
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# --- Status right ---
$pfx = "#{?client_prefix,#[fg=$($p.red)]#[bg=$($p.bg0)]${sRL}#[bg=$($p.red)]#[fg=$($p.bg0),bold] ${iPrefix}PREF #[fg=$($p.red)]#[bg=$($p.bg0)]${sLR},}"
$right = "${pfx}"
$right += "#[fg=$($p.bg2),bg=$($p.bg0)]${sRL}"
$right += "#[fg=$($p.blue),bg=$($p.bg2)] ${iClock}%H:%M "
$right += "#[fg=$($p.bg3),bg=$($p.bg2)]${sRL}"
$right += "#[fg=$($p.yellow),bg=$($p.bg3)] ${iCal}%a "
$right += "#[fg=$($p.green),bg=$($p.bg3)]${sRL}"
$right += "#[fg=$($p.bg0),bg=$($p.green),bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# --- Window tabs ---
& $PSMUX set -g window-status-format "#[fg=$($p.bg1),bg=$($p.bg0)]${wL}#[fg=$($p.gray),bg=$($p.bg1)] ${iWin}#I  #W #[fg=$($p.bg1),bg=$($p.bg0)]${wR}" 2>&1 | Out-Null
& $PSMUX set -g window-status-current-format "#[fg=$($p.aqua),bg=$($p.bg0)]${wL}#[fg=$($p.bg0),bg=$($p.aqua),bold] ${iWin}#I  #W #[fg=$($p.aqua),bg=$($p.bg0)]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-activity-style "fg=$($p.orange),bg=$($p.bg0)" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($p.green)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.bg1)" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$($p.bg1),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.bg1),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$($p.green),fg=$($p.bg0)" 2>&1 | Out-Null

Write-Host "psmux-theme-everforest: loaded ($variant-$contrast, sep=$separator)" -ForegroundColor DarkGray
