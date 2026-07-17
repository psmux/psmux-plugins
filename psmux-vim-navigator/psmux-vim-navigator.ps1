#!/usr/bin/env pwsh
# =============================================================================
# psmux-vim-navigator - Seamless vim-aware pane navigation for psmux
# Port of christoomey/vim-tmux-navigator (tmux side) for psmux
# =============================================================================
#
# Prefix-less Ctrl+h/j/k/l pane navigation. When the active pane is running
# vim/nvim/view/fzf, the key is passed through to that program instead of
# switching panes, so vim's own <C-h/j/k/l> split navigation keeps working
# seamlessly alongside psmux pane navigation.
#
# Requires psmux's immediate-child pane_current_command strategy (shipped
# since psmux commit b003802, see psmux/psmux#299): idle panes report the
# shell name (pwsh/bash), and panes running vim/nvim report "vim"/"nvim"
# directly -- exactly what the detection below matches against.
#
# IMPLEMENTATION NOTE: upstream vim-tmux-navigator binds each key straight to
# `if-shell -F '<pattern>' 'send-keys <key>' 'select-pane -<dir>'` so the
# condition is (re)checked on every keystroke. As of psmux 3.3.6, a key bound
# directly to if-shell/run-shell registers fine and the condition itself
# evaluates correctly on demand, but the chosen branch never actually fires
# when the binding is triggered by a real keypress (verified empirically;
# root cause: src/commands.rs's if-shell/run-shell handlers forward the
# command to the server's control port and discard the result whenever
# app.control_port is set, which is true for every attached client -- see
# the psmux-plugins#1 comment thread for the full writeup). Until that is
# fixed upstream, this plugin instead runs a lightweight background poller
# (scripts/poll-vim-state.ps1) that watches #{pane_current_command} for the
# active pane and re-binds the direction keys between two plain,
# non-conditional commands (which DO dispatch correctly on every keypress)
# whenever vim starts or exits. This gives the same end-user behavior as
# upstream, with a bounded lag of one poll interval (default 250ms) right
# after vim/nvim is launched or quit in the active pane.
#
# Options (all optional, defaults match christoomey/vim-tmux-navigator where
# applicable):
#   set -g @vim_navigator_mapping_left   'C-h'
#   set -g @vim_navigator_mapping_down   'C-j'
#   set -g @vim_navigator_mapping_up     'C-k'
#   set -g @vim_navigator_mapping_right  'C-l'
#   set -g @vim_navigator_mapping_prev   'C-\'
#   set -g @vim_navigator_prefix_mapping_clear_screen 'C-l'
#   set -g @vim_navigator_pattern '(^|/)g?(view|l?n?vim?x?|fzf)(diff)?(\.exe)?$'
#   set -g @vim_navigator_poll_interval_ms '250'
# =============================================================================

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux', 'pmux', 'tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

function Get-PsmuxOption {
    param([string]$Name, [string]$Default)
    $val = (& $PSMUX show-options -g -v $Name 2>&1 | Out-String).Trim()
    if ($val -and $val -notmatch 'unknown|error|invalid') { return $val }
    return $Default
}

# --- Read options ---
$moveLeft  = Get-PsmuxOption '@vim_navigator_mapping_left'  'C-h'
$moveDown  = Get-PsmuxOption '@vim_navigator_mapping_down'  'C-j'
$moveUp    = Get-PsmuxOption '@vim_navigator_mapping_up'    'C-k'
$moveRight = Get-PsmuxOption '@vim_navigator_mapping_right' 'C-l'
$movePrev  = Get-PsmuxOption '@vim_navigator_mapping_prev'  'C-\'
$clearKey  = Get-PsmuxOption '@vim_navigator_prefix_mapping_clear_screen' 'C-l'
$vimPattern = Get-PsmuxOption '@vim_navigator_pattern' '(^|/)g?(view|l?n?vim?x?|fzf)(diff)?(\.exe)?$'
$pollIntervalMs = Get-PsmuxOption '@vim_navigator_poll_interval_ms' '250'

# --- Initial (non-vim) bindings, so navigation works immediately ---
& $PSMUX bind-key -n $moveLeft  'select-pane -L' 2>&1 | Out-Null
& $PSMUX bind-key -n $moveDown  'select-pane -D' 2>&1 | Out-Null
& $PSMUX bind-key -n $moveUp    'select-pane -U' 2>&1 | Out-Null
& $PSMUX bind-key -n $moveRight 'select-pane -R' 2>&1 | Out-Null
if ($movePrev) { & $PSMUX bind-key -n $movePrev 'select-pane -l' 2>&1 | Out-Null }

# copy-mode-vi table: always navigate directly (no vim process to defer to
# while already inside psmux's own copy mode). Plain commands, not subject
# to the if-shell dispatch issue.
& $PSMUX bind-key -T copy-mode-vi $moveLeft  'select-pane -L' 2>&1 | Out-Null
& $PSMUX bind-key -T copy-mode-vi $moveDown  'select-pane -D' 2>&1 | Out-Null
& $PSMUX bind-key -T copy-mode-vi $moveUp    'select-pane -U' 2>&1 | Out-Null
& $PSMUX bind-key -T copy-mode-vi $moveRight 'select-pane -R' 2>&1 | Out-Null
if ($movePrev) { & $PSMUX bind-key -T copy-mode-vi $movePrev 'select-pane -l' 2>&1 | Out-Null }

# Restore prefix + C-l as clear-screen (upstream convention, since C-l is
# claimed by the no-prefix binding above).
if ($clearKey) {
    & $PSMUX bind-key $clearKey "send-keys $clearKey" 2>&1 | Out-Null
}

# --- Start the background vim-state poller (single instance per user) ---
$SCRIPTS_DIR = Join-Path $PSScriptRoot 'scripts'
$pollScript = (Join-Path $SCRIPTS_DIR 'poll-vim-state.ps1') -replace '\\', '/'
$lockFile = (Join-Path $env:USERPROFILE '.psmux\vim-navigator.pid') -replace '\\', '/'

$pollArgs = @(
    '-NoProfile', '-File', $pollScript,
    '-PsmuxBin', $PSMUX,
    '-Pattern', $vimPattern,
    '-IntervalMs', $pollIntervalMs,
    '-KeyLeft', $moveLeft, '-KeyDown', $moveDown, '-KeyUp', $moveUp, '-KeyRight', $moveRight,
    '-KeyPrev', $movePrev,
    '-LockFile', $lockFile
)
try {
    Start-Process -FilePath 'pwsh' -ArgumentList $pollArgs -WindowStyle Hidden | Out-Null
} catch {
    Write-Host "psmux-vim-navigator: could not start background poller ($_)" -ForegroundColor Yellow
}

Write-Host "psmux-vim-navigator: loaded" -ForegroundColor DarkGray
