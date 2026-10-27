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
# Each key is bound as upstream binds it,
# `if-shell -F '<pattern>' 'send-keys <key>' 'select-pane -<dir>'`, so the
# server checks the pane that receives the key, on every keystroke, in every
# session. Older psmux releases dropped a key-bound if-shell, which is why
# this plugin used to rebind the keys from a background poller.
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

# A poller left running by an earlier version of this plugin would keep
# rebinding the keys below to plain commands, so stop it.
$lockFile = Join-Path $env:USERPROFILE '.psmux\vim-navigator.pid'
if (Test-Path $lockFile) {
    $oldPid = (Get-Content $lockFile -Raw -EA SilentlyContinue).Trim()
    if ($oldPid -match '^\d+$') {
        $old = Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid" -EA SilentlyContinue
        if ($old -and $old.CommandLine -match 'poll-vim-state') {
            Stop-Process -Id ([int]$oldPid) -Force -EA SilentlyContinue
        }
    }
    Remove-Item $lockFile -Force -EA SilentlyContinue
}

# --- Root table: vim-aware, checked on every keystroke ---
$isVim = "#{m/r:$vimPattern,#{pane_current_command}}"
& $PSMUX bind-key -n $moveLeft  if-shell -F $isVim "send-keys $moveLeft"  'select-pane -L' 2>&1 | Out-Null
& $PSMUX bind-key -n $moveDown  if-shell -F $isVim "send-keys $moveDown"  'select-pane -D' 2>&1 | Out-Null
& $PSMUX bind-key -n $moveUp    if-shell -F $isVim "send-keys $moveUp"    'select-pane -U' 2>&1 | Out-Null
& $PSMUX bind-key -n $moveRight if-shell -F $isVim "send-keys $moveRight" 'select-pane -R' 2>&1 | Out-Null
if ($movePrev) { & $PSMUX bind-key -n $movePrev if-shell -F $isVim "send-keys $movePrev" 'select-pane -l' 2>&1 | Out-Null }

# copy-mode-vi table: always navigate directly (no vim process to defer to
# while already inside psmux's own copy mode).
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

Write-Host "psmux-vim-navigator: loaded" -ForegroundColor DarkGray
