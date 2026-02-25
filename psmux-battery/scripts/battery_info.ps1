$ErrorActionPreference = 'SilentlyContinue'
$b = Get-CimInstance Win32_Battery
if ($b) {
    $pct = $b.EstimatedChargeRemaining
    $st = switch ($b.BatteryStatus) { 1 {'Discharging'} 2 {'Charging'} 3 {'Charged'} default {'Unknown'} }
    psmux display-message "Battery: ${pct}% ($st)"
} else {
    psmux display-message "No battery detected (AC power)"
}
