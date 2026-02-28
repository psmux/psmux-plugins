#!/usr/bin/env pwsh
# =============================================================================
# psmux-theme-dracula - Dracula color theme for psmux (Enhanced)
# =============================================================================
#
# A dark theme based on the Dracula color palette.
# https://draculatheme.com
#
# Options:
#   set -g @dracula-show-powerline 'on'      # powerline glyphs
#   set -g @dracula-separator 'arrow'        # arrow|rounded|slant
#   set -g @dracula-show-icons 'on'          # nerd font icons
#   set -g @dracula-show-left-icon 'session' # session|window|rocket
#   set -g @dracula-show-flags 'on'          # window flags
#   set -g @dracula-show-user 'on'           # username segment
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

$showPowerline = Get-Opt '@dracula-show-powerline' 'on'
$separator     = Get-Opt '@dracula-separator' 'arrow'
$showIcons     = Get-Opt '@dracula-show-icons' 'on'
$leftIcon      = Get-Opt '@dracula-show-left-icon' 'session'
$showFlags     = Get-Opt '@dracula-show-flags' 'on'
$showUser      = Get-Opt '@dracula-show-user' 'on'

$bg='#282a36'; $fg='#f8f8f2'; $curLine='#44475a'; $comment='#6272a4'
$cyan='#8be9fd'; $green='#50fa7b'; $orange='#ffb86c'; $pink='#ff79c6'
$purple='#bd93f9'; $red='#ff5555'; $yellow='#f1fa8c'

switch ($separator) {
    'rounded' { $sLR=''; $sRL=''; $wL=''; $wR='' }
    'slant'   { $sLR=''; $sRL=''; $wL=''; $wR='' }
    default   { $sLR=''; $sRL=''; $wL=''; $wR='' }
}
if ($showPowerline -ne 'on') { $sLR=' '; $sRL=' '; $wL=' '; $wR=' ' }

if ($showIcons -eq 'on') {
    $iSess=' '; $iWin=' '; $iRocket=' '
    $iClock=' '; $iCal='󰃭 '; $iUser=' '; $iPfx='󰌌 '
} else { $iSess=''; $iWin=''; $iRocket=''; $iClock=''; $iCal=''; $iUser=''; $iPfx='' }

switch ($leftIcon) {
    'window' { $lG=$iWin; $lT='#W' }
    'rocket' { $lG=$iRocket; $lT='#S' }
    default  { $lG=$iSess; $lT='#S' }
}
$fl = if ($showFlags -eq 'on') { '#{?window_flags,#{window_flags}, }' } else { '' }

& $PSMUX set -g status on 2>&1 | Out-Null
& $PSMUX set -g status-position bottom 2>&1 | Out-Null
& $PSMUX set -g status-justify left 2>&1 | Out-Null
& $PSMUX set -g status-interval 5 2>&1 | Out-Null
& $PSMUX set -g status-style "bg=$bg,fg=$fg" 2>&1 | Out-Null

$left = "#[bg=$green,fg=$bg,bold] ${lG}${lT} #[fg=$green,bg=$curLine]${sLR}"
if ($showUser -eq 'on') {
    $left += "#[fg=$fg,bg=$curLine] ${iUser}#(whoami) #[fg=$curLine,bg=$bg]${sLR} "
} else { $left += "#[fg=$curLine,bg=$bg]${sLR} " }
& $PSMUX set -g status-left $left 2>&1 | Out-Null
& $PSMUX set -g status-left-length 45 2>&1 | Out-Null

$pfx = "#{?client_prefix,#[fg=$yellow]#[bg=$bg]${sRL}#[bg=$yellow]#[fg=$bg,bold] ${iPfx}WAIT #[fg=$yellow]#[bg=$bg]${sLR},}"
$right = "${pfx}#[fg=$curLine,bg=$bg]${sRL}#[fg=$cyan,bg=$curLine] ${iClock}%H:%M #[fg=$comment,bg=$curLine]${sRL}#[fg=$orange,bg=$comment] ${iCal}%a #[fg=$purple,bg=$comment]${sRL}#[fg=$fg,bg=$purple,bold] ${iCal}%d-%b "
& $PSMUX set -g status-right $right 2>&1 | Out-Null
& $PSMUX set -g status-right-length 80 2>&1 | Out-Null

& $PSMUX set -g window-status-format "#[fg=$curLine,bg=$bg]${wL}#[fg=$fg,bg=$curLine] ${iWin}#I  #W${fl}#[fg=$curLine,bg=$bg]${wR}" 2>&1 | Out-Null
& $PSMUX set -g window-status-current-format "#[fg=$purple,bg=$bg]${wL}#[fg=$fg,bg=$purple,bold] ${iWin}#I  #W${fl}#[fg=$purple,bg=$bg]${wR}" 2>&1 | Out-Null

& $PSMUX set -g window-status-activity-style "fg=$orange,bg=$bg" 2>&1 | Out-Null
& $PSMUX set -g pane-active-border-style "fg=$purple" 2>&1 | Out-Null
& $PSMUX set -g pane-border-style "fg=$curLine" 2>&1 | Out-Null
& $PSMUX set -g message-style "bg=$curLine,fg=$fg" 2>&1 | Out-Null
& $PSMUX set -g message-command-style "bg=$curLine,fg=$fg" 2>&1 | Out-Null
& $PSMUX set -g mode-style "bg=$purple,fg=$fg" 2>&1 | Out-Null

Write-Host "psmux-theme-dracula: loaded (sep=$separator)" -ForegroundColor DarkGray
