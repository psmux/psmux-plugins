#!/usr/bin/env pwsh
# Query Windows system stats
$ErrorActionPreference = 'SilentlyContinue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

# --- CPU Usage ---
$cpu = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
if (-not $cpu) { $cpu = 0 }
$cpuRounded = [math]::Round($cpu, 0)

# CPU color
$cpuColor = if ($cpuRounded -lt 30) { '#[fg=green]' }
            elseif ($cpuRounded -lt 80) { '#[fg=yellow]' }
            else { '#[fg=red]' }

# --- Memory Usage ---
$os = Get-CimInstance -ClassName Win32_OperatingSystem
if ($os) {
    $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeMem = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedMem = [math]::Round($totalMem - $freeMem, 1)
    $memPercent = [math]::Round(($usedMem / $totalMem) * 100, 0)
} else {
    $totalMem = 0; $usedMem = 0; $memPercent = 0
}

# Memory color
$memColor = if ($memPercent -lt 50) { '#[fg=green]' }
            elseif ($memPercent -lt 80) { '#[fg=yellow]' }
            else { '#[fg=red]' }

# --- Build display strings ---
$cpuDisplay = "${cpuColor}CPU:${cpuRounded}%#[default]"
$memDisplay = "${memColor}MEM:${memPercent}%#[default]"

# Store as psmux options
& $PSMUX set -g @cpu_percentage "${cpuRounded}%" 2>&1 | Out-Null
& $PSMUX set -g @cpu_display "$cpuDisplay" 2>&1 | Out-Null
& $PSMUX set -g @ram_percentage "${memPercent}%" 2>&1 | Out-Null
& $PSMUX set -g @ram_display "$memDisplay" 2>&1 | Out-Null
& $PSMUX set -g @ram_used "${usedMem}G" 2>&1 | Out-Null
& $PSMUX set -g @ram_total "${totalMem}G" 2>&1 | Out-Null

# Inject into status-right if placeholders exist
$currentRight = (& $PSMUX show-options -g -v status-right 2>&1 | Out-String).Trim()
$modified = $false

if ($currentRight -match '\{cpu\}') {
    $currentRight = $currentRight -replace '\{cpu\}', $cpuDisplay
    $modified = $true
}
if ($currentRight -match '\{ram\}') {
    $currentRight = $currentRight -replace '\{ram\}', $memDisplay
    $modified = $true
}

if ($modified) {
    & $PSMUX set -g status-right "$currentRight" 2>&1 | Out-Null
}
