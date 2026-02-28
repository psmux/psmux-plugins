#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-kanagawa - Kanagawa color theme for psmux
# Inspired by the famous painting "The Great Wave off Kanagawa"
# =============================================================================
#
# A dark theme inspired by the colors of Katsushika Hokusai's artwork.
# https://github.com/rebelot/kanagawa.nvim
#
# Variants: wave (default), dragon, lotus
#
# Options:
#   set -g @kanagawa-variant 'wave'          # wave|dragon|lotus
#   set -g @kanagawa-show-powerline 'on'     # powerline arrows
#   set -g @kanagawa-separator 'arrow'       # arrow|rounded|slant
#   set -g @kanagawa-show-icons 'on'         # nerd font icons
#   set -g @kanagawa-show-user 'on'          # username in left segment
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
$showUser      = Get-Opt '@kanagawa-show-user' 'on'

# --- Palettes ---
$palettes = @{
    wave = @{
        bg='#1f1f28'; bg_dark='#16161d'; bg_light='#2a2a37'
        fg='#dcd7ba'; fg_dark='#c8c093'; fg_comment='#727169'
        wave1='#223249'; wave2='#2d4f67'
        samurai='#e82424'; autumn_red='#e46876'; autumn_yellow='#dca561'
        spring_blue='#7fb4ca'; spring_green='#98bb6c'; spring_violet='#9cabca'
        crystal='#7e9cd8'; surimi='#ffa066'; fuji_gray='#54546d'
        sakura='#d27e99'; carp='#e6c384'; dragon_blue='#658594'
    }
    dragon = @{
        bg='#181616'; bg_dark='#0d0c0c'; bg_light='#282727'
        fg='#c5c9c5'; fg_dark='#a6a69c'; fg_comment='#625e5a'
        wave1='#12120f'; wave2='#282727'
        samurai='#c4746e'; autumn_red='#c4746e'; autumn_yellow='#c4b28a'
        spring_blue='#8ba4b0'; spring_green='#87a987'; spring_violet='#8992a7'
        crystal='#8ba4b0'; surimi='#b6927b'; fuji_gray='#4c4b4b'
        sakura='#a292a3'; carp='#c4b28a'; dragon_blue='#658594'
    }
    lotus = @{
        bg='#f2ecbc'; bg_dark='#e5ddb0'; bg_light='#f9f3c7'
        fg='#545464'; fg_dark='#43436c'; fg_comment='#8a8980'
        wave1='#e5ddb0'; wave2='#d7d0a5'
        samurai='#c84053'; autumn_red='#d7474b'; autumn_yellow='#cc6d00'
        spring_blue='#6693bf'; spring_green='#6f894e'; spring_violet='#624c83'
        crystal='#5d57a3'; surimi='#cc6d00'; fuji_gray='#b5b4a7'
        sakura='#b35b79'; carp='#77713f'; dragon_blue='#5a7785'
    }
}

$p = $palettes[$variant]
if (-not $p) { $p = $palettes['wave'] }

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
    $iSess  = '󰊠 '; $iWin = ' '; $iClock = ' '
    $iCal   = '󰃭 '; $iUser = ' '; $iPrefix = '󰌌 '
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
& $PSMUX set -g status-style "bg=$($p.bg),fg=$($p.fg)" 2>&1 | Out-Null

# --- Status left ---
$left = "#[bg=$($p.crystal),fg=$($p.bg),bold] ${iSess}#S "
$left += "#[fg=$($p.crystal),bg=$($p.wave1)]${sLR}"

if ($showUser -eq 'on') {
    $left += "#[fg=$($p.fg_dark),bg=$($p.wave1)] ${iUser}#(whoami) "
    $left += "#[fg=$($p.wave1),bg=$($p.bg)]${sLR} "
} else {
    $left += "#[fg=$($p.wave1),bg=$($p.bg)]${sLR} "
}

& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# --- Status right ---
$pfx = "#{?client_prefix,#[fg=$($p.samurai)]#[bg=$($p.bg)]${sRL}#[bg=$($p.samurai)]#[fg=$($p.bg),bold] ${iPrefix}PREF #[fg=$($p.samurai)]#[bg=$($p.bg)]${sLR},}"

$right = "${pfx}"
$right += "#[fg=$($p.wave1),bg=$($p.bg)]${sRL}"
$right += "#[fg=$($p.spring_green),bg=$($p.wave1)] ${iClock}%H:%M "
$right += "#[fg=$($p.wave2),bg=$($p.wave1)]${sRL}"
$right += "#[fg=$($p.autumn_yellow),bg=$($p.wave2)] ${iCal}%a "
$right += "#[fg=$($p.crystal),bg=$($p.wave2)]${sRL}"
$right += "#[fg=$($p.bg),bg=$($p.crystal),bold] ${iCal}%d-%b "

& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# --- Window tabs ---
& $PSMUX set -g window-status-format "#[fg=$($p.wave1),bg=$($p.bg)]${wL}#[fg=$($p.fg_comment),bg=$($p.wave1)] ${iWin}#I  #W #[fg=$($p.wave1),bg=$($p.bg)]${wR}" 2>&1 | Out-Null
& $PSMUX set -g window-status-current-format "#[fg=$($p.spring_green),bg=$($p.bg)]${wL}#[fg=$($p.bg),bg=$($p.spring_green),bold] ${iWin}#I  #W #[fg=$($p.spring_green),bg=$($p.bg)]${wR}" 2>&1 | Out-Null

# Activity, borders, messages
& $PSMUX set -g window-status-activity-style "fg=$($p.surimi),bg=$($p.bg)" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($p.crystal)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.wave1)" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$($p.wave1),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.wave1),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$($p.wave2),fg=$($p.fg)" 2>&1 | Out-Null

Write-Host "psmux-theme-kanagawa: loaded ($variant, sep=$separator)" -ForegroundColor DarkGray
