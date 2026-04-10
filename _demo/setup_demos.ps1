#!/usr/bin/env pwsh
# Demo setup: 3 sessions, each with their own plugins
# Uses $PSScriptRoot to resolve all paths dynamically (no hardcoded user paths)
$ErrorActionPreference = 'Continue'

# Resolve plugin root from _demo/ parent directory
$pluginRoot = (Resolve-Path "$PSScriptRoot\..").Path

$cpuScript  = ("$pluginRoot/psmux-cpu/scripts/system_stats.ps1") -replace '\\', '/'
$batScript  = ("$pluginRoot/psmux-battery/scripts/battery_status.ps1") -replace '\\', '/'
$gitScript  = ("$pluginRoot/psmux-git-status/scripts/git_status.ps1") -replace '\\', '/'
$netScript  = ("$pluginRoot/psmux-net-speed/scripts/net_speed.ps1") -replace '\\', '/'

# Default working directory: user home
$defaultDir = $HOME

# --- Session 1: system-monitor (CPU + RAM + Battery) ---
Write-Host "Creating system-monitor session..."
psmux new-session -d -s "system-monitor" -c $defaultDir
psmux -t "system-monitor" set -g status-right " #{@cpu_display} #{@ram_display} #{@battery_display}  %H:%M "
psmux -t "system-monitor" set -g status-interval 5
psmux -t "system-monitor" set -g "@cpu_display" ""
psmux -t "system-monitor" set -g "@ram_display" ""
psmux -t "system-monitor" set -g "@battery_display" ""
psmux -t "system-monitor" set-hook -ga status-interval "run-shell 'pwsh -NoProfile -File `"$cpuScript`"'"
psmux -t "system-monitor" set-hook -ga status-interval "run-shell 'pwsh -NoProfile -File `"$batScript`"'"
psmux -t "system-monitor" set-hook -ga client-attached "run-shell 'pwsh -NoProfile -File `"$cpuScript`"'"
psmux -t "system-monitor" set-hook -ga client-attached "run-shell 'pwsh -NoProfile -File `"$batScript`"'"

# Initial data poll for system-monitor
$env:PSMUX_TARGET_SESSION = "system-monitor"
& pwsh -NoProfile -File "$pluginRoot\psmux-cpu\scripts\system_stats.ps1" 2>&1 | Out-Null
& pwsh -NoProfile -File "$pluginRoot\psmux-battery\scripts\battery_status.ps1" 2>&1 | Out-Null

# --- Session 2: dev-workspace (Git status) ---
Write-Host "Creating dev-workspace session..."
psmux new-session -d -s "dev-workspace" -c $defaultDir
psmux -t "dev-workspace" set -g status-right " #{@git_status}  %H:%M "
psmux -t "dev-workspace" set -g status-interval 5
psmux -t "dev-workspace" set -g "@git_status" ""
psmux -t "dev-workspace" set -g "@git_branch" ""
psmux -t "dev-workspace" set-hook -ga status-interval "run-shell 'pwsh -NoProfile -File `"$gitScript`"'"
psmux -t "dev-workspace" set-hook -ga client-attached "run-shell 'pwsh -NoProfile -File `"$gitScript`"'"

# Initial data poll for dev-workspace
$env:PSMUX_TARGET_SESSION = "dev-workspace"
& pwsh -NoProfile -File "$pluginRoot\psmux-git-status\scripts\git_status.ps1" 2>&1 | Out-Null

# --- Session 3: network-tools (Net speed) ---
Write-Host "Creating network-tools session..."
psmux new-session -d -s "network-tools" -c $defaultDir
psmux -t "network-tools" set -g status-right " #{@net_speed_display}  %H:%M "
psmux -t "network-tools" set -g status-interval 5
psmux -t "network-tools" set -g "@net_speed_display" ""
psmux -t "network-tools" set -g "@net_speed_down" ""
psmux -t "network-tools" set -g "@net_speed_up" ""
psmux -t "network-tools" set-hook -ga status-interval "run-shell 'pwsh -NoProfile -File `"$netScript`"'"
psmux -t "network-tools" set-hook -ga client-attached "run-shell 'pwsh -NoProfile -File `"$netScript`"'"

# Initial data poll for network-tools
$env:PSMUX_TARGET_SESSION = "network-tools"
& pwsh -NoProfile -File "$pluginRoot\psmux-net-speed\scripts\net_speed.ps1" 2>&1 | Out-Null

# Clean up env
Remove-Item Env:\PSMUX_TARGET_SESSION -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Demo sessions created:" -ForegroundColor Green
psmux list-sessions
