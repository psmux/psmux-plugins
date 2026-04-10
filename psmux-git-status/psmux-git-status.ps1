#!/usr/bin/env pwsh
# =============================================================================
# psmux-git-status - Git branch & status in psmux status bar
# =============================================================================
#
# Shows current git branch, status indicators (dirty/clean/ahead/behind),
# and commit info in the status bar. Essential for developer workflows.
#
# Usage in status-right or status-left:
#   set -g status-right '#{git_status} | %H:%M'
#
# Options:
#   set -g @git-status-show-branch 'on'
#   set -g @git-status-show-dirty 'on'
#   set -g @git-status-show-ahead-behind 'on'
#   set -g @git-status-show-stash 'on'
#   set -g @git-status-clean-symbol '✓'
#   set -g @git-status-dirty-symbol '✗'
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
$SCRIPTS_DIR = Join-Path $PSScriptRoot 'scripts'

if (-not (Test-Path $SCRIPTS_DIR)) {
    New-Item -ItemType Directory -Path $SCRIPTS_DIR -Force | Out-Null
}

# --- Create git status script ---
$gitScript = @'
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
    $branchIcon = '󰜘'  # detached icon
} else {
    $branchIcon = ''  # branch icon
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

# Build display string
$parts = @()
$parts += "#[fg=magenta]${branchIcon} ${branch}#[default]"

if ($staged -gt 0)    { $parts += "#[fg=green]󰐕${staged}#[default]" }
if ($modified -gt 0)  { $parts += "#[fg=yellow]${modified}#[default]" }
if ($untracked -gt 0) { $parts += "#[fg=red]${untracked}#[default]" }
if ($conflicts -gt 0) { $parts += "#[fg=red,bold]${conflicts}#[default]" }

if ($ahead -gt 0)  { $parts += "#[fg=cyan]⇡${ahead}#[default]" }
if ($behind -gt 0) { $parts += "#[fg=yellow]⇣${behind}#[default]" }

if ($stashCount -gt 0) { $parts += "#[fg=blue]󰆓${stashCount}#[default]" }

# Clean indicator
if ($staged -eq 0 -and $modified -eq 0 -and $untracked -eq 0 -and $conflicts -eq 0) {
    $parts += "#[fg=green]✓#[default]"
}

$display = $parts -join ' '

& $PSMUX set -g '@git_status' "$display" 2>&1 | Out-Null
& $PSMUX set -g '@git_branch' "$branch" 2>&1 | Out-Null
'@

$gitScriptPath = Join-Path $SCRIPTS_DIR 'git_status.ps1'
Set-Content -Path $gitScriptPath -Value $gitScript -Force

# --- Set up polling ---
$pollCmd = ("pwsh -NoProfile -File `"$gitScriptPath`"") -replace '\\', '/'
& $PSMUX set-hook -g client-attached "run-shell '$pollCmd'" 2>&1 | Out-Null
& $PSMUX set-hook -g status-interval "run-shell '$pollCmd'" 2>&1 | Out-Null

# Initial poll
& pwsh -NoProfile -File $gitScriptPath 2>&1 | Out-Null

# --- Keybinding for detailed git info ---
$infoScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$panePath = (psmux display-message -p '#{pane_current_path}' 2>&1 | Out-String).Trim()
if (-not $panePath) { $panePath = $PWD.Path }
$branch = (git -C $panePath symbolic-ref --short HEAD 2>&1 | Out-String).Trim()
$lastCommit = (git -C $panePath log --oneline -1 2>&1 | Out-String).Trim()
$status = git -C $panePath status --short 2>&1
$fileCount = @($status).Count
psmux display-message "Git: $branch | $fileCount changed | $lastCommit"
'@

$infoPath = Join-Path $SCRIPTS_DIR 'git_info.ps1'
Set-Content -Path $infoPath -Value $infoScript -Force
$infoFwd = $infoPath -replace '\\', '/'

& $PSMUX bind-key C-g "run-shell 'pwsh -NoProfile -File \"$infoFwd\"'" 2>&1 | Out-Null

Write-Host "psmux-git-status: loaded (use #{git_status} in status-right/left)" -ForegroundColor DarkGray
