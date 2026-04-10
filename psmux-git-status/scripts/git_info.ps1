$ErrorActionPreference = 'SilentlyContinue'
$panePath = (psmux display-message -p '#{pane_current_path}' 2>&1 | Out-String).Trim()
if (-not $panePath) { $panePath = $PWD.Path }
$branch = (git -C $panePath symbolic-ref --short HEAD 2>&1 | Out-String).Trim()
$lastCommit = (git -C $panePath log --oneline -1 2>&1 | Out-String).Trim()
$status = git -C $panePath status --short 2>&1
$fileCount = @($status).Count
psmux display-message "Git: $branch | $fileCount changed | $lastCommit"
