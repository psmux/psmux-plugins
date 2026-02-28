#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-catppuccin - Catppuccin color theme for psmux
# Port of catppuccin/tmux for psmux
# =============================================================================
#
# A soothing pastel theme for psmux.
# https://catppuccin.com
#
# Flavors: latte (light), frappe, macchiato, mocha (dark, default)
#
# Options:
#   set -g @catppuccin-flavor 'mocha'             # latte|frappe|macchiato|mocha
#   set -g @catppuccin-separator-style 'rounded'  # arrow|rounded|slanted|none
#   set -g @catppuccin-show-user 'on'             # show username segment
#   set -g @catppuccin-show-host 'off'            # show hostname segment
#   set -g @catppuccin-show-pane-count 'on'       # show pane count badge
#   set -g @catppuccin-show-zoom 'on'             # show zoom indicator
#   set -g @catppuccin-show-sync 'on'             # show sync indicator
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

$flavor    = Get-Opt '@catppuccin-flavor' 'mocha'
$sepStyle  = Get-Opt '@catppuccin-separator-style' 'rounded'
$showUser  = Get-Opt '@catppuccin-show-user' 'on'
$showHost  = Get-Opt '@catppuccin-show-host' 'off'
$showPanes = Get-Opt '@catppuccin-show-pane-count' 'on'
$showZoom  = Get-Opt '@catppuccin-show-zoom' 'on'
$showSync  = Get-Opt '@catppuccin-show-sync' 'on'

# --- Color palettes by flavor ---
$palettes = @{
    mocha = @{
        rosewater = '#f5e0dc'; flamingo  = '#f2cdcd'; pink    = '#f5c2e7'
        mauve     = '#cba6f7'; red       = '#f38ba8'; maroon  = '#eba0ac'
        peach     = '#fab387'; yellow    = '#f9e2af'; green   = '#a6e3a1'
        teal      = '#94e2d5'; sky       = '#89dceb'; sapphire = '#74c7ec'
        blue      = '#89b4fa'; lavender  = '#b4befe'
        text      = '#cdd6f4'; subtext1  = '#bac2de'; subtext0 = '#a6adc8'
        overlay2  = '#9399b2'; overlay1  = '#7f849c'; overlay0 = '#6c7086'
        surface2  = '#585b70'; surface1  = '#45475a'; surface0 = '#313244'
        base      = '#1e1e2e'; mantle    = '#181825'; crust   = '#11111b'
    }
    macchiato = @{
        rosewater = '#f4dbd6'; flamingo  = '#f0c6c6'; pink    = '#f5bde6'
        mauve     = '#c6a0f6'; red       = '#ed8796'; maroon  = '#ee99a0'
        peach     = '#f5a97f'; yellow    = '#eed49f'; green   = '#a6da95'
        teal      = '#8bd5ca'; sky       = '#91d7e3'; sapphire = '#7dc4e4'
        blue      = '#8aadf4'; lavender  = '#b7bdf8'
        text      = '#cad3f5'; subtext1  = '#b8c0e0'; subtext0 = '#a5adcb'
        overlay2  = '#939ab7'; overlay1  = '#8087a2'; overlay0 = '#6e738d'
        surface2  = '#5b6078'; surface1  = '#494d64'; surface0 = '#363a4f'
        base      = '#24273a'; mantle    = '#1e2030'; crust   = '#181926'
    }
    frappe = @{
        rosewater = '#f2d5cf'; flamingo  = '#eebebe'; pink    = '#f4b8e4'
        mauve     = '#ca9ee6'; red       = '#e78284'; maroon  = '#ea999c'
        peach     = '#ef9f76'; yellow    = '#e5c890'; green   = '#a6d189'
        teal      = '#81c8be'; sky       = '#99d1db'; sapphire = '#85c1dc'
        blue      = '#8caaee'; lavender  = '#babbf1'
        text      = '#c6d0f5'; subtext1  = '#b5bfe2'; subtext0 = '#a5adce'
        overlay2  = '#949cbb'; overlay1  = '#838ba7'; overlay0 = '#737994'
        surface2  = '#626880'; surface1  = '#51576d'; surface0 = '#414559'
        base      = '#303446'; mantle    = '#292c3c'; crust   = '#232634'
    }
    latte = @{
        rosewater = '#dc8a78'; flamingo  = '#dd7878'; pink    = '#ea76cb'
        mauve     = '#8839ef'; red       = '#d20f39'; maroon  = '#e64553'
        peach     = '#fe640b'; yellow    = '#df8e1d'; green   = '#40a02b'
        teal      = '#179299'; sky       = '#04a5e5'; sapphire = '#209fb5'
        blue      = '#1e66f5'; lavender  = '#7287fd'
        text      = '#4c4f69'; subtext1  = '#5c5f77'; subtext0 = '#6c6f85'
        overlay2  = '#7c7f93'; overlay1  = '#8c8fa1'; overlay0 = '#9ca0b0'
        surface2  = '#acb0be'; surface1  = '#bcc0cc'; surface0 = '#ccd0da'
        base      = '#eff1f5'; mantle    = '#e6e9ef'; crust   = '#dce0e8'
    }
}

$p = $palettes[$flavor]
if (-not $p) { $p = $palettes['mocha'] }

# --- Separators ---
# Active tabs use full powerline arrows; inactive use thin sub-separators
switch ($sepStyle) {
    'arrow'   { $lSep = ''; $rSep = ''; $wL = ''; $wR = ''; $wLThin = ''; $wRThin = '' }
    'rounded' { $lSep = ''; $rSep = ''; $wL = ''; $wR = ''; $wLThin = ''; $wRThin = '' }
    'slanted' { $lSep = ''; $rSep = ''; $wL = ''; $wR = ''; $wLThin = ''; $wRThin = '' }
    default   { $lSep = ' '; $rSep = ' '; $wL = ' '; $wR = ' '; $wLThin = ' '; $wRThin = ' ' }
}

# --- Status indicators (conditionals) ---
$zoomInd = ''
if ($showZoom -eq 'on') {
    $zoomInd = "#{?window_zoomed_flag,#[fg=$($p.yellow)] 󰁌 ,}"
}
$syncInd = ''
if ($showSync -eq 'on') {
    $syncInd = "#{?pane_synchronized,#[fg=$($p.peach)]#[bg=$($p.base)]${rSep}#[bg=$($p.peach)]#[fg=$($p.crust),bold] 󰓦 SYNC #[fg=$($p.peach)]#[bg=$($p.base)]${lSep},}"
}
$paneCount = ''
if ($showPanes -eq 'on') {
    $paneCount = "#{?#{e|>:#{window_panes}#,1},#[fg=$($p.overlay2)]  #{window_panes},}"
}

# =============================================================================
# APPLY THEME
# =============================================================================

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$($p.base),fg=$($p.text)" 2>&1 | Out-Null
# Seamless powerline: no gap between tabs
& $PSMUX set -g window-status-separator "" 2>&1 | Out-Null

# Status left: session icon + name + optional user/host
$stLeft = "#[bg=$($p.blue),fg=$($p.crust),bold]  #S #[fg=$($p.blue),bg=$($p.surface0)]${lSep}"
if ($showUser -eq 'on') {
    $stLeft += "#[fg=$($p.subtext0),bg=$($p.surface0)]  #(whoami) "
}
if ($showHost -eq 'on') {
    $stLeft += "#[fg=$($p.surface1),bg=$($p.surface0)]#[fg=$($p.sky),bg=$($p.surface1)] 󰒋 #H "
}
$stLeft += "#[fg=$($p.surface0),bg=$($p.base)]${lSep} "
& $PSMUX set -g status-left $stLeft 2>&1 | Out-Null
& $PSMUX set -g status-left-length 50 2>&1 | Out-Null

# Status right: prefix indicator + sync + time + day + date gradient with icons
$prefixInd = "#{?client_prefix,#[fg=$($p.peach)]#[bg=$($p.base)]${rSep}#[bg=$($p.peach)]#[fg=$($p.crust),bold] 󰌌 PREF #[fg=$($p.peach)]#[bg=$($p.base)]${lSep},}"
& $PSMUX set -g status-right "${prefixInd}${syncInd}#[fg=$($p.surface1),bg=$($p.base)]${rSep}#[fg=$($p.sky),bg=$($p.surface1)]  %H:%M #[fg=$($p.surface2),bg=$($p.surface1)]${rSep}#[fg=$($p.yellow),bg=$($p.surface2)] 󰃰 %a #[fg=$($p.mauve),bg=$($p.surface2)]${rSep}#[fg=$($p.crust),bg=$($p.mauve),bold] 󰨲 %d-%b " 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

# Window status (inactive): thin sub-separators for lighter visual weight
& $PSMUX set -g window-status-format "#[fg=$($p.surface1),bg=$($p.base)]${wLThin}#[fg=$($p.subtext0),bg=$($p.surface1)]  #I  #W #{?window_flags,#{window_flags},}${paneCount}#[fg=$($p.surface1),bg=$($p.base)]${wRThin}" 2>&1 | Out-Null

# Window status (current/active): full powerline separators, bold + zoom/pane indicators
& $PSMUX set -g window-status-current-format "#[fg=$($p.green),bg=$($p.base)]${wL}#[fg=$($p.crust),bg=$($p.green),bold]  #I  #W #{?window_flags,#{window_flags},}${zoomInd}${paneCount}#[fg=$($p.green),bg=$($p.base)]${wR}" 2>&1 | Out-Null

# Last-used window gets underline accent
& $PSMUX set -g window-status-last-style "underscore" 2>&1 | Out-Null

# Activity: bold + distinct color
& $PSMUX set -g window-status-activity-style "fg=$($p.peach),bg=$($p.base),bold" 2>&1 | Out-Null

# Bell: red bold flash
& $PSMUX set -g window-status-bell-style "fg=$($p.red),bg=$($p.base),bold" 2>&1 | Out-Null

# Pane borders
& $PSMUX set -g pane-active-border-style "fg=$($p.blue)" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$($p.surface0)" 2>&1 | Out-Null

# Messages
& $PSMUX set -g message-style "bg=$($p.surface0),fg=$($p.text)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$($p.surface0),fg=$($p.text)" 2>&1 | Out-Null

# Copy mode
& $PSMUX set -g mode-style "bg=$($p.blue),fg=$($p.crust)" 2>&1 | Out-Null

Write-Host "psmux-theme-catppuccin: loaded ($flavor)" -ForegroundColor DarkGray
