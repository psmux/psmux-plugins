#!/usr/bin/env pwsh
# "nvim session strategy"
#
# Restores an nvim session from 'Session.vim' if present in the pane's
# directory. Mirrors tmux-resurrect's strategies/nvim_session.sh.

param(
    [Parameter(Mandatory)] [string] $OriginalCommand,
    [Parameter(Mandatory)] [string] $Directory
)

$dir = $Directory -replace '^~', $env:USERPROFILE
$sessionFile = Join-Path $dir 'Session.vim'

if (Test-Path $sessionFile) {
    'nvim -S'
} elseif ($OriginalCommand -match '\-S\b') {
    'nvim'
} else {
    $OriginalCommand
}
