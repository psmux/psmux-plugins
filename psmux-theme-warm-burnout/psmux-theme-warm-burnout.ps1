#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-warm-burnout - Warm Burnout theme for psmux
# =============================================================================
#
# Minimal warm color theme ported from felipefdl/warm-burnout.
# Supports the original dark and light variants.
# https://github.com/felipefdl/warm-burnout
#
# Options:
#   set -g @warm-burnout-variant 'dark'   # dark|light
# =============================================================================

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($name in @('psmux', 'pmux', 'tmux')) {
        $bin = Get-Command $name -ErrorAction SilentlyContinue
        if ($bin) { return $bin.Source }
    }
    return 'psmux'
}

function Get-PsmuxOption {
    param([string]$Name, [string]$Default)

    $value = (& $PSMUX show-options -g -v $Name 2>&1 | Out-String).Trim()
    if ($value -and $value -notmatch 'unknown|error|invalid|^$') { return $value }
    return $Default
}

$PSMUX = Get-PsmuxBin

$palettes = @{
    dark = @{
        StatusFg        = '#b4a89c'
        StatusBg        = '#14120f'
        SessionFg       = '#ffb454'
        SessionBg       = '#14120f'
        ActiveWindowFg  = '#14120f'
        ActiveWindowBg  = '#ff8f40'
        WindowFg        = '#b4a89c'
        WindowBg        = '#14120f'
        PaneBorder      = '#222018'
        ActivePaneBorder= '#b8522e'
        MessageFg       = '#bfbdb6'
        MessageBg       = '#1f1d17'
        ModeFg          = '#1a1510'
        ModeBg          = '#f5c56e'
        ClockColor      = '#f5c56e'
    }
    light = @{
        StatusFg        = '#544c40'
        StatusBg        = '#EDE6DA'
        SessionFg       = '#855700'
        SessionBg       = '#EDE6DA'
        ActiveWindowFg  = '#EDE6DA'
        ActiveWindowBg  = '#924800'
        WindowFg        = '#544c40'
        WindowBg        = '#EDE6DA'
        PaneBorder      = '#DDD6CA'
        ActivePaneBorder= '#b8522e'
        MessageFg       = '#3a3630'
        MessageBg       = '#F0E8DC'
        ModeFg          = '#F5EDE0'
        ModeBg          = '#8a6600'
        ClockColor      = '#8a6600'
    }
}

$variant = (Get-PsmuxOption '@warm-burnout-variant' 'dark').ToLowerInvariant()
$palette = $palettes[$variant]
if (-not $palette) {
    $variant = 'dark'
    $palette = $palettes[$variant]
}

& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify centre 2>&1 | Out-Null
& $PSMUX set -g status-style "fg=$($palette.StatusFg),bg=$($palette.StatusBg)" 2>&1 | Out-Null

& $PSMUX set -g status-left ' #S ' 2>&1 | Out-Null
& $PSMUX set -g status-left-length 20 2>&1 | Out-Null
& $PSMUX set -g status-left-style "fg=$($palette.SessionFg),bg=$($palette.SessionBg)" 2>&1 | Out-Null

& $PSMUX set -g status-right '' 2>&1 | Out-Null
& $PSMUX set -g status-right-length 0 2>&1 | Out-Null

& $PSMUX set -g window-status-format ' #I:#W ' 2>&1 | Out-Null
& $PSMUX set -g window-status-current-format ' #I:#W ' 2>&1 | Out-Null
& $PSMUX set -g window-status-current-style "fg=$($palette.ActiveWindowFg),bg=$($palette.ActiveWindowBg),bold" 2>&1 | Out-Null
& $PSMUX set -g window-status-style "fg=$($palette.WindowFg),bg=$($palette.WindowBg)" 2>&1 | Out-Null
& $PSMUX set -g window-status-separator '' 2>&1 | Out-Null

& $PSMUX set -g pane-border-style "fg=$($palette.PaneBorder)" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$($palette.ActivePaneBorder)" 2>&1 | Out-Null

& $PSMUX set -g message-style "fg=$($palette.MessageFg),bg=$($palette.MessageBg)" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "fg=$($palette.MessageFg),bg=$($palette.MessageBg)" 2>&1 | Out-Null

& $PSMUX set -g mode-style "fg=$($palette.ModeFg),bg=$($palette.ModeBg)" 2>&1 | Out-Null
& $PSMUX set -g clock-mode-colour $palette.ClockColor 2>&1 | Out-Null

Write-Host "psmux-theme-warm-burnout: loaded ($variant)" -ForegroundColor DarkGray