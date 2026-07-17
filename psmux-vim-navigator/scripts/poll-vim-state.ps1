#!/usr/bin/env pwsh
# =============================================================================
# psmux-vim-navigator background poller
# =============================================================================
# WHY THIS EXISTS (read before "simplifying" this away):
#
# The upstream vim-tmux-navigator mechanism binds each direction key straight
# to `if-shell -F '<vim-detect-regex>' 'send-keys <key>' 'select-pane -<dir>'`
# so tmux evaluates the condition fresh on every keystroke. psmux 3.3.6
# accepts and *registers* that exact binding fine, and the condition itself
# evaluates correctly when queried directly (`display-message -p`) -- but the
# bound `if-shell` command never actually fires its chosen branch when
# triggered by a real keypress. Root cause (psmux source,
# src/commands.rs ~line 1865): execute_command_string()'s "if-shell"/"if"
# match arm forwards the raw command to the server's control port via
# send_control_to_port() and discards the response whenever
# app.control_port is Some(..) -- which is true for essentially every
# attached client. The fully-correct local evaluation logic (parse
# condition, run format/shell test, dispatch the chosen branch) exists right
# below it, but is dead code in practice because control_port is always set.
# `run-shell` has the identical pattern and is equally dead when key-bound.
# Reported upstream as part of psmux/psmux-plugins#1.
#
# WORKAROUND: instead of asking psmux to evaluate a condition per keystroke,
# this script polls #{pane_current_command} for the active pane and
# *statically* re-binds C-h/j/k/l/prev between the two known-good, always-
# dispatching commands (`select-pane -<dir>` / `send-keys <key>`) whenever
# the vim/non-vim state changes. Plain, non-conditional bind-key commands do
# dispatch correctly on every real keypress (verified), so the binding that
# is active at the moment of a keystroke behaves exactly like the upstream
# per-keystroke check would -- with a bounded lag of one poll interval right
# after vim/nvim starts or exits in the active pane.
# =============================================================================
param(
    [Parameter(Mandatory)][string]$PsmuxBin,
    [string]$Socket = '',
    [string]$Pattern = '(^|/)g?(view|l?n?vim?x?|fzf)(diff)?(\.exe)?$',
    [int]$IntervalMs = 250,
    [string]$KeyLeft = 'C-h',
    [string]$KeyDown = 'C-j',
    [string]$KeyUp = 'C-k',
    [string]$KeyRight = 'C-l',
    [string]$KeyPrev = 'C-\',
    [string]$LockFile
)

function Invoke-Psmux {
    param([string[]]$Args)
    if ($Socket) {
        & $PsmuxBin -L $Socket @Args 2>&1
    } else {
        & $PsmuxBin @Args 2>&1
    }
}

# --- Single-instance guard ---
if ($LockFile -and (Test-Path $LockFile)) {
    $existingPid = (Get-Content $LockFile -Raw -EA SilentlyContinue).Trim()
    if ($existingPid -match '^\d+$') {
        $existing = Get-Process -Id ([int]$existingPid) -EA SilentlyContinue
        if ($existing -and $existing.ProcessName -match 'pwsh|powershell') {
            exit 0   # another poller is already running for this socket
        }
    }
}
if ($LockFile) {
    New-Item -ItemType Directory -Path (Split-Path $LockFile) -Force -EA SilentlyContinue | Out-Null
    Set-Content -Path $LockFile -Value $PID -Force
}

function Set-NavBindings {
    param([bool]$IsVim)
    if ($IsVim) {
        Invoke-Psmux @('bind-key','-n',$KeyLeft,"send-keys $KeyLeft")   | Out-Null
        Invoke-Psmux @('bind-key','-n',$KeyDown,"send-keys $KeyDown")   | Out-Null
        Invoke-Psmux @('bind-key','-n',$KeyUp,"send-keys $KeyUp")       | Out-Null
        Invoke-Psmux @('bind-key','-n',$KeyRight,"send-keys $KeyRight") | Out-Null
        if ($KeyPrev) { Invoke-Psmux @('bind-key','-n',$KeyPrev,"send-keys $KeyPrev") | Out-Null }
    } else {
        Invoke-Psmux @('bind-key','-n',$KeyLeft,'select-pane -L')  | Out-Null
        Invoke-Psmux @('bind-key','-n',$KeyDown,'select-pane -D')  | Out-Null
        Invoke-Psmux @('bind-key','-n',$KeyUp,'select-pane -U')    | Out-Null
        Invoke-Psmux @('bind-key','-n',$KeyRight,'select-pane -R') | Out-Null
        if ($KeyPrev) { Invoke-Psmux @('bind-key','-n',$KeyPrev,'select-pane -l') | Out-Null }
    }
}

$lastState = $null
$consecutiveFailures = 0

while ($true) {
    $cmd = (Invoke-Psmux @('display-message','-p','#{pane_current_command}') | Out-String).Trim()
    if (-not $cmd -or $cmd -match 'no server running|no session|error') {
        $consecutiveFailures++
        if ($consecutiveFailures -ge 20) {
            # psmux is gone (server killed / all sessions closed) -- stop polling.
            if ($LockFile) { Remove-Item $LockFile -Force -EA SilentlyContinue }
            exit 0
        }
        Start-Sleep -Milliseconds $IntervalMs
        continue
    }
    $consecutiveFailures = 0

    $isVim = $cmd -match $Pattern
    if ($isVim -ne $lastState) {
        Set-NavBindings -IsVim $isVim
        $lastState = $isVim
    }
    Start-Sleep -Milliseconds $IntervalMs
}
