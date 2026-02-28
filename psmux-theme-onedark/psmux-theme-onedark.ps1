#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-onedark - One Dark color theme for psmux
# =============================================================================
#
# Inspired by Atom's iconic One Dark theme.
# Clean, modern dark theme with vibrant accent colors.
#
# Options:
#   set -g @onedark-show-powerline 'on'
#   set -g @onedark-separator 'arrow'       # arrow|rounded|slant
#   set -g @onedark-show-icons 'on'
#   set -g @onedark-show-user 'on'
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

# --- One Dark palette ---
$p = @{
    bg        = '#282c34'
    bg_light  = '#2c313a'
    bg_lighter = '#3e4452'
    gutter    = '#4b5263'
    fg        = '#abb2bf'
    comment   = '#5c6370'
    red       = '#e06c75'
    dark_red  = '#be5046'
    green     = '#98c379'
    yellow    = '#e5c07b'
    dark_yellow = '#d19a66'
    blue      = '#61afef'
    magenta   = '#c678dd'
    cyan      = '#56b6c2'
}

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
    $iSess = ' '; $iWin = ' '; $iClock = ' '
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
& $PSMUX set -g status-style "bg=$($p.bg),fg=$($p.fg)" 2>&1 | Out-Null

# --- Status left ---
$left = "#[bg=$($p.blue),fg=$($p.bg),bold] ${iSess}#S "
$left += "#[fg=$($p.blue),bg=$($p.bg_light)]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$($p.fg),bg=$($p.bg_light)] ${iUser}#(whoami) "
    $left += "#[fg=$($p.bg_light),bg=$($p.bg)]${sLR} "
} else {
    $left += "#[fg=$($p.bg_light),bg=$($p.bg)]${sLR} "
}
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

# --- Status right ---
$pfx = "#{?client_prefix,#[fg=$($p.red)]#[bg=$($p.bg)]${sRL}#[bg=$($p.red)]#[fg=$($p.bg),bold] ${iPrefix}PREF #[fg=$($p.red)]#[bg=$($p.bg)]${sLR},}"
$right = "${pfx}"
$right += "#[fg=$($p.bg_lighter),bg=$($p.bg)]${sRL}"
$right += "#[fg=$($p.cyan),bg=$($p.bg_lighter)] ${iClock}%H:%M "
$right += "#[fg=$($p.gutter),bg=$($p.bg_lighter)]${sRL}"
$right += "#[fg=$($p.yellow),bg=$($p.gutter)] ${iCal}%a "
$right += "#[fg=$($p.blue),bg=$($p.gutter)]${sRL}"
$right += "#[fg=$($p.bg),bg=$($p.blue),bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# --- Window tabs ---
& $PSMUX set -g window-status-format "#[fg=$($p.bg_light),bg=$($p.bg)]${wL}#[fg=$($p.comment),bg=$($p.bg_light)] ${iWin}#I  #W #[fg=$($p.bg_light),bg=$($p.bg)]${wR}" 2>&1 | Out-Null
& $PSMUX set -g window-status-current-format "#[fg=$($p.green),bg=$($p.bg)]${wL}#[fg=$($p.bg),bg=$($p.green),bold] ${iWin}#I  #W #[fg=$($p.green),bg=$($p.bg)]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-activity-style "fg=$($p.dark_yellow),bg=$($p.bg)" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($p.blue)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.bg_lighter)" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$($p.bg_light),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.bg_light),fg=$($p.fg)" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$($p.blue),fg=$($p.bg)" 2>&1 | Out-Null

Write-Host "psmux-theme-onedark: loaded (sep=$separator)" -ForegroundColor DarkGray
