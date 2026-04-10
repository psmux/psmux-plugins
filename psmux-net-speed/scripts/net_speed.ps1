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

function Format-Speed {
    param([double]$BytesPerSec)
    if ($BytesPerSec -ge 1GB) { return "{0:N1} GB/s" -f ($BytesPerSec / 1GB) }
    if ($BytesPerSec -ge 1MB) { return "{0:N1} MB/s" -f ($BytesPerSec / 1MB) }
    if ($BytesPerSec -ge 1KB) { return "{0:N0} KB/s" -f ($BytesPerSec / 1KB) }
    return "{0:N0} B/s" -f $BytesPerSec
}

function Format-SpeedCompact {
    param([double]$BytesPerSec)
    if ($BytesPerSec -ge 1GB) { return "{0:N1}G" -f ($BytesPerSec / 1GB) }
    if ($BytesPerSec -ge 1MB) { return "{0:N1}M" -f ($BytesPerSec / 1MB) }
    if ($BytesPerSec -ge 1KB) { return "{0:N0}K" -f ($BytesPerSec / 1KB) }
    return "{0:N0}B" -f $BytesPerSec
}

# Get active network adapter
$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
if (-not $adapters) {
    & $PSMUX set -g '@net_speed_display' '#[fg=red]󰖪 offline#[default]' 2>&1 | Out-Null
    exit
}

# Use state file for delta calculation
$stateFile = Join-Path $env:TEMP 'psmux_net_speed.json'

# Get current byte counts
$stats = Get-NetAdapterStatistics -Name $adapters[0].Name -ErrorAction SilentlyContinue
if (-not $stats) {
    & $PSMUX set -g '@net_speed_display' '#[fg=yellow]󰖩 --#[default]' 2>&1 | Out-Null
    exit
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$rxNow = [double]$stats.ReceivedBytes
$txNow = [double]$stats.SentBytes

# Read previous state
$rxSpeed = 0.0; $txSpeed = 0.0
if (Test-Path $stateFile) {
    $prev = Get-Content $stateFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($prev -and $prev.ts) {
        $elapsed = ($now - $prev.ts) / 1000.0
        if ($elapsed -gt 0 -and $elapsed -lt 60) {
            $rxSpeed = ($rxNow - $prev.rx) / $elapsed
            $txSpeed = ($txNow - $prev.tx) / $elapsed
            if ($rxSpeed -lt 0) { $rxSpeed = 0 }
            if ($txSpeed -lt 0) { $txSpeed = 0 }
        }
    }
}

# Save current state
@{ ts = $now; rx = $rxNow; tx = $txNow } | ConvertTo-Json | Set-Content $stateFile -Force

# Format display
$rxStr = Format-SpeedCompact -BytesPerSec $rxSpeed
$txStr = Format-SpeedCompact -BytesPerSec $txSpeed

$display = "#[fg=cyan]󰇚 ${rxStr}#[default] #[fg=magenta]󰕒 ${txStr}#[default]"

& $PSMUX set -g '@net_speed_display' "$display" 2>&1 | Out-Null
& $PSMUX set -g '@net_speed_down' "$rxStr" 2>&1 | Out-Null
& $PSMUX set -g '@net_speed_up' "$txStr" 2>&1 | Out-Null

# Inject into status-right if placeholder exists
$currentRight = (& $PSMUX show-options -g -v status-right 2>&1 | Out-String).Trim()
if ($currentRight -match '\{net_speed\}') {
    $currentRight = $currentRight -replace '\{net_speed\}', $display
    & $PSMUX set -g status-right "$currentRight" 2>&1 | Out-Null
}
