#!/usr/bin/env pwsh
# =============================================================================
# psmux-prefix-highlight - Highlight status bar when prefix key is pressed
# Port of tmux-plugins/tmux-prefix-highlight for psmux
# =============================================================================
#
# Shows a visual indicator in the status bar when:
# - Prefix key is pressed (waiting for next key)
# - Copy mode is active
# - Sync panes mode is active
#
# Options:
#   set -g @prefix_highlight_fg 'white'
#   set -g @prefix_highlight_bg 'blue'
#   set -g @prefix_highlight_prefix_prompt 'Wait'
#   set -g @prefix_highlight_copy_prompt 'Copy'
#   set -g @prefix_highlight_sync_prompt 'Sync'
#   set -g @prefix_highlight_show_copy_mode 'on'
#   set -g @prefix_highlight_show_sync_mode 'on'
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

# --- Read options with defaults ---
function Get-PluginOption {
    param([string]$Name, [string]$Default)
    $val = (& $PSMUX show-options -g -v $Name 2>&1 | Out-String).Trim()
    if ($val -and $val -notmatch 'unknown|error|invalid') { return $val }
    return $Default
}

$fg = Get-PluginOption '@prefix_highlight_fg' 'white'
$bg = Get-PluginOption '@prefix_highlight_bg' 'blue'
$prefixPrompt = Get-PluginOption '@prefix_highlight_prefix_prompt' 'Wait'
$copyPrompt = Get-PluginOption '@prefix_highlight_copy_prompt' 'Copy'
$syncPrompt = Get-PluginOption '@prefix_highlight_sync_prompt' 'Sync'
$showCopy = Get-PluginOption '@prefix_highlight_show_copy_mode' 'on'
$showSync = Get-PluginOption '@prefix_highlight_show_sync_mode' 'on'

# --- Build the highlight format string ---
# Uses psmux format conditionals:
#   #{?client_prefix,...}  - true when prefix key is pressed
#   #{?pane_in_mode,...}   - true when in copy mode
#   #{?synchronize-panes,...} - true when sync panes is on

$highlight = "#{?client_prefix,#[fg=$fg]#[bg=$bg] $prefixPrompt ,}"

if ($showCopy -eq 'on') {
    $highlight += "#{?pane_in_mode,#[fg=$fg]#[bg=yellow] $copyPrompt ,}"
}

if ($showSync -eq 'on') {
    $highlight += "#{?synchronize-panes,#[fg=$fg]#[bg=red] $syncPrompt ,}"
}

# --- Inject into status-right ---
# Get current status-right, prepend the highlight
$currentRight = (& $PSMUX show-options -g -v status-right 2>&1 | Out-String).Trim()
if (-not $currentRight -or $currentRight -match 'unknown|error') {
    $currentRight = '%H:%M %d-%b-%y'
}

# Only add if not already present
if ($currentRight -notmatch 'prefix_highlight|client_prefix') {
    $newRight = "$highlight $currentRight"
    & $PSMUX set -g status-right "$newRight" 2>&1 | Out-Null
}

Write-Host "psmux-prefix-highlight: loaded" -ForegroundColor DarkGray
