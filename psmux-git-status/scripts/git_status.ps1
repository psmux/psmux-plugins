#!/usr/bin/env pwsh
$ErrorActionPreference = 'SilentlyContinue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

# Get current pane's working directory
$panePath = (& $PSMUX display-message -p '#{pane_current_path}' 2>&1 | Out-String).Trim()
if (-not $panePath -or $panePath -match 'error|unknown') {
    $panePath = $PWD.Path
}

# Check if we're in a git repo
$gitCheck = git -C $panePath rev-parse --is-inside-work-tree 2>&1
if ($gitCheck -ne 'true') {
    & $PSMUX set -g '@git_status' '' 2>&1 | Out-Null
    exit
}

# Get branch name
$branch = (git -C $panePath symbolic-ref --short HEAD 2>&1 | Out-String).Trim()
if (-not $branch -or $branch -match 'fatal') {
    # Detached HEAD
    $branch = (git -C $panePath rev-parse --short HEAD 2>&1 | Out-String).Trim()
    $branchIcon = [char]0x2387  # detached icon (alternative key)
} else {
    $branchIcon = [char]0x2325  # branch icon (option key symbol)
}

# Get status
$status = git -C $panePath status --porcelain 2>&1
$staged = @($status | Where-Object { $_ -match '^[MADRC]' }).Count
$modified = @($status | Where-Object { $_ -match '^.[MD]' }).Count
$untracked = @($status | Where-Object { $_ -match '^\?\?' }).Count
$conflicts = @($status | Where-Object { $_ -match '^(DD|AU|UD|UA|DU|AA|UU)' }).Count

# Ahead/behind
$abInfo = (git -C $panePath rev-list --count --left-right '@{upstream}...HEAD' 2>&1 | Out-String).Trim()
$ahead = 0; $behind = 0
if ($abInfo -match '^(\d+)\s+(\d+)$') {
    $behind = [int]$Matches[1]
    $ahead = [int]$Matches[2]
}

# Stash count
$stashCount = @(git -C $panePath stash list 2>&1).Count

# Build display string using standard Unicode symbols (no Nerd Fonts required)
$parts = @()
$parts += "#[fg=magenta]${branchIcon} ${branch}#[default]"

if ($staged -gt 0)    { $parts += "#[fg=green]+${staged}#[default]" }
if ($modified -gt 0)  { $parts += "#[fg=yellow]~${modified}#[default]" }
if ($untracked -gt 0) { $parts += "#[fg=red]?${untracked}#[default]" }
if ($conflicts -gt 0) { $parts += "#[fg=red,bold]!${conflicts}#[default]" }

if ($ahead -gt 0)  { $parts += "#[fg=cyan]$([char]0x2191)${ahead}#[default]" }
if ($behind -gt 0) { $parts += "#[fg=yellow]$([char]0x2193)${behind}#[default]" }

if ($stashCount -gt 0) { $parts += "#[fg=blue]$([char]0x2261)${stashCount}#[default]" }

# Clean indicator
if ($staged -eq 0 -and $modified -eq 0 -and $untracked -eq 0 -and $conflicts -eq 0) {
    $parts += "#[fg=green]$([char]0x2713)#[default]"
}

$display = $parts -join ' '

& $PSMUX set -g '@git_status' "$display" 2>&1 | Out-Null
& $PSMUX set -g '@git_branch' "$branch" 2>&1 | Out-Null
