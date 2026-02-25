#!/usr/bin/env pwsh
# =============================================================================
# psmux-sidebar - Directory tree sidebar for psmux
# Port of tmux-plugins/tmux-sidebar for psmux
# =============================================================================
#
# Opens a sidebar pane showing the directory tree for the current pane's
# working directory. Uses 'tree' command or PowerShell Get-ChildItem fallback.
#
# Key bindings:
#   Prefix + Tab     - Toggle sidebar
#   Prefix + BTab    - Toggle sidebar (focus sidebar)
#
# Options:
#   set -g @sidebar-tree-command 'tree'    # command to generate tree
#   set -g @sidebar-width '40'             # sidebar width in columns
#   set -g @sidebar-position 'left'        # 'left' or 'right'
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

# --- Create sidebar toggle script ---
$sidebarScript = @'
#!/usr/bin/env pwsh
# Toggle a directory tree sidebar pane
param(
    [switch]$FocusSidebar
)

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

# Read options
function Get-Opt {
    param([string]$Name, [string]$Default)
    $v = (& $PSMUX show-options -g -v $Name 2>&1 | Out-String).Trim()
    if ($v -and $v -notmatch 'unknown|error|invalid') { return $v }
    return $Default
}

$width = Get-Opt '@sidebar-width' '40'
$position = Get-Opt '@sidebar-position' 'left'

# Check if sidebar is already open
$sidebarActive = (& $PSMUX show-options -g -v '@sidebar-pane-id' 2>&1 | Out-String).Trim()

if ($sidebarActive -and $sidebarActive -match '^%\d+$') {
    # Try to find and close the sidebar pane
    $panes = (& $PSMUX list-panes 2>&1) | Out-String
    if ($panes -match [regex]::Escape($sidebarActive)) {
        & $PSMUX kill-pane -t $sidebarActive 2>&1 | Out-Null
        & $PSMUX set -g @sidebar-pane-id '' 2>&1 | Out-Null
        & $PSMUX display-message 'Sidebar closed' 2>&1 | Out-Null
        exit 0
    } else {
        # Pane no longer exists, clear the option
        & $PSMUX set -g @sidebar-pane-id '' 2>&1 | Out-Null
    }
}

# Get current working directory
$cwd = (& $PSMUX display-message -p '#{pane_current_path}' 2>&1 | Out-String).Trim()
if (-not $cwd) { $cwd = $env:USERPROFILE }

# Determine tree command
$treeCmd = Get-Opt '@sidebar-tree-command' ''
if (-not $treeCmd) {
    # Check if 'tree' is available
    $hasTree = Get-Command tree -ErrorAction SilentlyContinue
    if ($hasTree) {
        $treeCmd = "tree /F /A `"$cwd`""
    } else {
        # PowerShell fallback: recursive listing
        $treeCmd = "pwsh -NoProfile -Command `"Get-ChildItem -Path '$cwd' -Recurse -Depth 3 -Name | ForEach-Object { Write-Host `$_ }; Read-Host 'Press Enter to close'`""
    }
}

# Create sidebar pane
$splitFlag = if ($position -eq 'right') { '-h' } else { '-hb' }

# Split and capture the new pane ID
$splitArgs = @('split-window', $splitFlag, '-l', $width, '-c', $cwd, '--', 'pwsh', '-NoProfile', '-Command',
    "Write-Host '  Directory: $cwd' -ForegroundColor Cyan; Write-Host ('=' * 38) -ForegroundColor DarkGray; $treeCmd; Read-Host '(Enter to close)'")

& $PSMUX @splitArgs 2>&1 | Out-Null

# Store the sidebar pane ID
$newPaneId = (& $PSMUX display-message -p '#{pane_id}' 2>&1 | Out-String).Trim()
& $PSMUX set -g @sidebar-pane-id "$newPaneId" 2>&1 | Out-Null

if (-not $FocusSidebar) {
    # Return focus to the original pane
    & $PSMUX last-pane 2>&1 | Out-Null
}
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'toggle_sidebar.ps1') -Value $sidebarScript -Force

# --- Register keybindings ---
$sidebarPath = (Join-Path $SCRIPTS_DIR 'toggle_sidebar.ps1') -replace '\\', '/'

& $PSMUX bind-key Tab "run-shell 'pwsh -NoProfile -File \"$sidebarPath\"'" 2>&1 | Out-Null
& $PSMUX bind-key BTab "run-shell 'pwsh -NoProfile -File \"$sidebarPath\" -FocusSidebar'" 2>&1 | Out-Null

Write-Host "psmux-sidebar: loaded (Prefix+Tab=toggle)" -ForegroundColor DarkGray
