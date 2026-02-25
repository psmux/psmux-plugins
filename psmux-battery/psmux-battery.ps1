#!/usr/bin/env pwsh
# =============================================================================
# psmux-battery - Battery status in psmux status bar
# Port of tmux-plugins/tmux-battery for psmux
# =============================================================================
#
# Displays battery percentage and charging status in the psmux status bar.
# Uses native Windows WMI/CIM for laptop battery info.
#
# Usage in status bar:
#   set -g status-right '#{battery_icon} #{battery_percentage} | %H:%M'
#
# Since psmux format variables are evaluated by the psmux binary itself,
# this plugin uses a different approach: it periodically updates a status
# bar format string with actual battery values via run-shell + set-option.
#
# Options:
#   set -g @batt_icon_charge_tier8 ''
#   set -g @batt_icon_charge_tier7 ''
#   set -g @batt_icon_charge_tier6 ''
#   set -g @batt_icon_charge_tier5 ''
#   set -g @batt_icon_charge_tier4 ''
#   set -g @batt_icon_charge_tier3 ''
#   set -g @batt_icon_charge_tier2 ''
#   set -g @batt_icon_charge_tier1 ''
#   set -g @batt_icon_status_charged '='
#   set -g @batt_icon_status_charging '+'
#   set -g @batt_icon_status_discharging '-'
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

# --- Create battery status script ---
$batteryScript = @'
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
    & $PSMUX set -g @battery_percentage 'AC' 2>&1 | Out-Null
    & $PSMUX set -g @battery_icon '=' 2>&1 | Out-Null
    & $PSMUX set -g @battery_status 'charged' 2>&1 | Out-Null
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
& $PSMUX set -g @battery_percentage "${percentage}%" 2>&1 | Out-Null
& $PSMUX set -g @battery_icon "$icon" 2>&1 | Out-Null
& $PSMUX set -g @battery_status "$status" 2>&1 | Out-Null
& $PSMUX set -g @battery_color "$color" 2>&1 | Out-Null
& $PSMUX set -g @battery_status_icon "$statusIcon" 2>&1 | Out-Null

# Build the battery display string
$display = "${color}${statusIcon}${percentage}%#[default]"

# Get current status-right and inject battery info
$currentRight = (& $PSMUX show-options -g -v status-right 2>&1 | Out-String).Trim()
if ($currentRight -match '\{battery\}') {
    $newRight = $currentRight -replace '\{battery\}', $display
    & $PSMUX set -g status-right "$newRight" 2>&1 | Out-Null
}
'@

$batteryScriptPath = Join-Path $SCRIPTS_DIR 'battery_status.ps1'
Set-Content -Path $batteryScriptPath -Value $batteryScript -Force

# --- Set up periodic battery polling via status-interval hook ---
# Update battery status every status-interval refresh
# NOTE: Convert backslashes to forward slashes — psmux strips backslashes
$pollCmd = ("pwsh -NoProfile -File `"$batteryScriptPath`"") -replace '\\', '/'
& $PSMUX set-hook -g client-attached "run-shell '$pollCmd'" 2>&1 | Out-Null

# Get initial battery status
& pwsh -NoProfile -File $batteryScriptPath 2>&1 | Out-Null

# --- Quick-access: Prefix+B shows detailed battery info ---
# Create a small helper script for the battery info keybinding.
# Inline pwsh -Command in bind-key breaks due to psmux escaping rules.
$infoScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$b = Get-CimInstance Win32_Battery
if ($b) {
    $pct = $b.EstimatedChargeRemaining
    $st = switch ($b.BatteryStatus) { 1 {'Discharging'} 2 {'Charging'} 3 {'Charged'} default {'Unknown'} }
    psmux display-message "Battery: ${pct}% ($st)"
} else {
    psmux display-message "No battery detected (AC power)"
}
'@

$infoScriptPath = Join-Path $SCRIPTS_DIR 'battery_info.ps1'
Set-Content -Path $infoScriptPath -Value $infoScript -Force
$infoPathFwd = $infoScriptPath -replace '\\', '/'

& $PSMUX bind-key b "run-shell 'pwsh -NoProfile -File \"$infoPathFwd\"'" 2>&1 | Out-Null

Write-Host "psmux-battery: loaded (use {battery} in status-right)" -ForegroundColor DarkGray
