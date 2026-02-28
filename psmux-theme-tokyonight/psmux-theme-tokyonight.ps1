#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-tokyonight - Tokyo Night color theme for psmux (Enhanced)
# =============================================================================
#
# A clean dark theme inspired by VS Code's Tokyo Night theme.
# https://github.com/folke/tokyonight.nvim
#
# Options:
#   set -g @tokyonight-style 'night'         # night|storm|moon
#   set -g @tokyonight-show-powerline 'on'
#   set -g @tokyonight-separator 'arrow'     # arrow|rounded|slant
#   set -g @tokyonight-show-icons 'on'
#   set -g @tokyonight-show-user 'on'
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

$palettes = @{
    night = @{
        bg='#1a1b26'; bg_dark='#16161e'; bg_float='#1a1b26'
        fg='#c0caf5'; fg_dark='#a9b1d6'; comment='#565f89'
        bg_hl='#292e42'; dark3='#545c7e'; dark5='#737aa2'
        blue='#7aa2f7'; cyan='#7dcfff'; green='#9ece6a'
        magenta='#bb9af7'; orange='#ff9e64'; red='#f7768e'; yellow='#e0af68'
    }
    storm = @{
        bg='#24283b'; bg_dark='#1f2335'; bg_float='#24283b'
        fg='#c0caf5'; fg_dark='#a9b1d6'; comment='#565f89'
        bg_hl='#292e42'; dark3='#545c7e'; dark5='#737aa2'
        blue='#7aa2f7'; cyan='#7dcfff'; green='#9ece6a'
        magenta='#bb9af7'; orange='#ff9e64'; red='#f7768e'; yellow='#e0af68'
    }
    moon = @{
        bg='#222436'; bg_dark='#1e2030'; bg_float='#222436'
        fg='#c8d3f5'; fg_dark='#b4c2f0'; comment='#636da6'
        bg_hl='#2f334d'; dark3='#545c7e'; dark5='#737aa2'
        blue='#82aaff'; cyan='#86e1fc'; green='#c3e88d'
        magenta='#fca7ea'; orange='#ff966c'; red='#ff757f'; yellow='#ffc777'
    }
}

$p = $palettes[$style]
if (-not $p) { $p = $palettes['night'] }

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
& $PSMUX set -g status-style "bg=$($p.bg),fg=$($p.fg)" 2>&1 | Out-Null

$left = "#[bg=$($p.blue),fg=$($p.bg),bold] ${iSess}#S #[fg=$($p.blue),bg=$($p.bg_hl)]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$($p.fg_dark),bg=$($p.bg_hl)] ${iUser}#(whoami) #[fg=$($p.bg_hl),bg=$($p.bg)]${sLR} "
} else { $left += "#[fg=$($p.bg_hl),bg=$($p.bg)]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

$pfx = "#{?client_prefix,#[fg=$($p.orange)]#[bg=$($p.bg)]${sRL}#[bg=$($p.orange)]#[fg=$($p.bg),bold] ${iPfx}PREF #[fg=$($p.orange)]#[bg=$($p.bg)]${sLR},}"
$right = "${pfx}#[fg=$($p.bg_hl),bg=$($p.bg)]${sRL}#[fg=$($p.cyan),bg=$($p.bg_hl)] ${iClock}%H:%M #[fg=$($p.dark3),bg=$($p.bg_hl)]${sRL}#[fg=$($p.magenta),bg=$($p.dark3)] ${iCal}%a #[fg=$($p.blue),bg=$($p.dark3)]${sRL}#[fg=$($p.bg),bg=$($p.blue),bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

& $PSMUX set -g window-status-format "#[fg=$($p.bg_hl),bg=$($p.bg)]${wL}#[fg=$($p.comment),bg=$($p.bg_hl)] ${iWin}#I  #W #[fg=$($p.bg_hl),bg=$($p.bg)]${wR}" 2>&1 | Out-Null
& $PSMUX set -g window-status-current-format "#[fg=$($p.green),bg=$($p.bg)]${wL}#[fg=$($p.bg),bg=$($p.green),bold] ${iWin}#I  #W #[fg=$($p.green),bg=$($p.bg)]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-activity-style "fg=$($p.orange),bg=$($p.bg)" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($p.blue)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.bg_hl)" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$($p.bg_hl),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.bg_hl),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$($p.blue),fg=$($p.bg)" 2>&1 | Out-Null

Write-Host "psmux-theme-tokyonight: loaded ($style, sep=$separator)" -ForegroundColor DarkGray
