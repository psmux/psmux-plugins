#!/usr/bin/env pwsh
# Query Windows battery status using CIM
$ErrorActionPreference = 'SilentlyContinue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

# Get battery info
$battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

if (-not $battery) {
    # No battery (desktop PC)
    & $PSMUX set -g '@battery_percentage' 'AC' 2>&1 | Out-Null
    & $PSMUX set -g '@battery_icon' '=' 2>&1 | Out-Null
    & $PSMUX set -g '@battery_status' 'charged' 2>&1 | Out-Null
    exit 0
}

$percentage = $battery.EstimatedChargeRemaining
$status = switch ($battery.BatteryStatus) {
    1 { 'discharging' }
    2 { 'charging' }
    3 { 'charged' }
    default { 'unknown' }
}

# Determine icon based on percentage tier
$icon = switch ([math]::Floor($percentage / 12.5)) {
    { $_ -ge 7 } { '█' }
    6 { '▇' }
    5 { '▆' }
    4 { '▅' }
    3 { '▄' }
    2 { '▃' }
    1 { '▂' }
    default { '▁' }
}

$statusIcon = switch ($status) {
    'charging' { '+' }
    'charged' { '=' }
    'discharging' { '-' }
    default { '?' }
}

# Color based on level
$color = if ($percentage -gt 50) { '#[fg=green]' }
         elseif ($percentage -gt 20) { '#[fg=yellow]' }
         else { '#[fg=red]' }

# Update psmux options
& $PSMUX set -g '@battery_percentage' "${percentage}%" 2>&1 | Out-Null
& $PSMUX set -g '@battery_icon' "$icon" 2>&1 | Out-Null
& $PSMUX set -g '@battery_status' "$status" 2>&1 | Out-Null
& $PSMUX set -g '@battery_color' "$color" 2>&1 | Out-Null
& $PSMUX set -g '@battery_status_icon' "$statusIcon" 2>&1 | Out-Null

# Build the battery display string
$display = "${color}${statusIcon}${percentage}%#[default]"
& $PSMUX set -g '@battery_display' "$display" 2>&1 | Out-Null

# Legacy: inject into status-right if it contains literal {battery} placeholder
$currentRight = (& $PSMUX show-options -g -v status-right 2>&1 | Out-String).Trim()
if ($currentRight -match '\{battery\}') {
    $newRight = $currentRight -replace '\{battery\}', $display
    & $PSMUX set -g status-right "$newRight" 2>&1 | Out-Null
}
