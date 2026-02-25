#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-dracula - Dracula color theme for psmux
# Port of dracula/tmux for psmux
# =============================================================================
#
# A dark theme based on the Dracula color palette.
# https://draculatheme.com
#
# Palette:
#   Background: #282a36    Current Line: #44475a
#   Foreground: #f8f8f2    Comment:      #6272a4
#   Cyan:       #8be9fd    Green:        #50fa7b
#   Orange:     #ffb86c    Pink:         #ff79c6
#   Purple:     #bd93f9    Red:          #ff5555
#   Yellow:     #f1fa8c
#
# Options:
#   set -g @dracula-show-powerline 'on'     # use powerline arrows
#   set -g @dracula-show-left-icon 'session' # 'session', 'window', or custom
#   set -g @dracula-border-contrast 'on'     # high contrast borders
#   set -g @dracula-show-flags 'on'          # show window flags
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

# --- Read theme options ---
$showPowerline = Get-Opt '@dracula-show-powerline' 'on'
$leftIcon = Get-Opt '@dracula-show-left-icon' 'session'
$borderContrast = Get-Opt '@dracula-border-contrast' 'off'
$showFlags = Get-Opt '@dracula-show-flags' 'on'

# --- Dracula colors ---
$bg       = '#282a36'
$fg       = '#f8f8f2'
$curLine  = '#44475a'
$comment  = '#6272a4'
$cyan     = '#8be9fd'
$green    = '#50fa7b'
$orange   = '#ffb86c'
$pink     = '#ff79c6'
$purple   = '#bd93f9'
$red      = '#ff5555'
$yellow   = '#f1fa8c'

# --- Powerline separators ---
if ($showPowerline -eq 'on') {
    $lSep = ''   # U+E0B0
    $rSep = ''   # U+E0B2
} else {
    $lSep = ''
    $rSep = ''
}

# --- Left icon ---
$leftIconStr = switch ($leftIcon) {
    'session'  { '#S' }
    'window'   { '#W' }
    default    { $leftIcon }
}

# --- Window flags ---
$flagStr = if ($showFlags -eq 'on') { '#{?window_flags,#{window_flags}, }' } else { '' }

# =============================================================================
# APPLY THEME
# =============================================================================

# Status bar
& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$bg,fg=$fg" 2>&1 | Out-Null

# Status left: [session]
if ($showPowerline -eq 'on') {
    & $PSMUX set -g status-left "#[bg=$green,fg=$bg,bold] $leftIconStr #[fg=$green,bg=$bg]$lSep " 2>&1 | Out-Null
    & $PSMUX set -g status-left-length 30 2>&1 | Out-Null
} else {
    & $PSMUX set -g status-left "#[bg=$green,fg=$bg,bold] $leftIconStr #[default] " 2>&1 | Out-Null
    & $PSMUX set -g status-left-length 20 2>&1 | Out-Null
}

# Status right: [prefix] time date
if ($showPowerline -eq 'on') {
    $prefixInd = "#{?client_prefix,#[fg=$yellow]#[bg=$bg]${rSep}#[bg=$yellow]#[fg=$bg] WAIT #[fg=$yellow]#[bg=$bg]${lSep},}"
    & $PSMUX set -g status-right "${prefixInd}#[fg=$curLine,bg=$bg]${rSep}#[fg=$fg,bg=$curLine] %H:%M #[fg=$purple,bg=$curLine]${rSep}#[fg=$bg,bg=$purple,bold] %d-%b-%y " 2>&1 | Out-Null
    & $PSMUX set -g status-right-length 60 2>&1 | Out-Null
} else {
    & $PSMUX set -g status-right "#{?client_prefix,#[fg=$bg,bg=$yellow] WAIT #[default],} #[fg=$fg,bg=$curLine] %H:%M #[fg=$bg,bg=$purple] %d-%b-%y " 2>&1 | Out-Null
    & $PSMUX set -g status-right-length 50 2>&1 | Out-Null
}

# Window status (inactive)
if ($showPowerline -eq 'on') {
    & $PSMUX set -g window-status-format "#[fg=$bg,bg=$curLine]${lSep}#[fg=$fg,bg=$curLine] #I:#W${flagStr} #[fg=$curLine,bg=$bg]${lSep}" 2>&1 | Out-Null
} else {
    & $PSMUX set -g window-status-format "#[fg=$fg,bg=$curLine] #I:#W${flagStr} " 2>&1 | Out-Null
}

# Window status (current/active)
if ($showPowerline -eq 'on') {
    & $PSMUX set -g window-status-current-format "#[fg=$bg,bg=$purple]${lSep}#[fg=$fg,bg=$purple,bold] #I:#W${flagStr} #[fg=$purple,bg=$bg]${lSep}" 2>&1 | Out-Null
} else {
    & $PSMUX set -g window-status-current-format "#[fg=$fg,bg=$purple,bold] #I:#W${flagStr} " 2>&1 | Out-Null
}

# Window activity
& $PSMUX set -g window-status-activity-style "fg=$orange,bg=$bg" 2>&1 | Out-Null

# Pane borders
$borderBg = if ($borderContrast -eq 'on') { $curLine } else { $bg }
& $PSMUX set -g pane-active-border-style "fg=$purple" 2>&1 | Out-Null

# Messages
& $PSMUX set -g message-style "bg=$curLine,fg=$fg" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$curLine,fg=$fg" 2>&1 | Out-Null

# Copy mode
& $PSMUX set -g mode-style "bg=$purple,fg=$fg" 2>&1 | Out-Null

Write-Host "psmux-theme-dracula: loaded" -ForegroundColor DarkGray
