#!/usr/bin/env pwsh
# =============================================================================
# psmux-cpu - CPU and memory usage in psmux status bar
# Port of tmux-plugins/tmux-cpu for psmux
# =============================================================================
#
# Shows CPU usage, memory usage, and GPU info in the status bar.
# Uses native Windows performance counters and CIM.
#
# Usage in status-right:
#   set -g status-right '{cpu} {ram} | %H:%M'
#
# Options:
#   set -g @cpu_low_fg_color '#[fg=green]'
#   set -g @cpu_medium_fg_color '#[fg=yellow]'
#   set -g @cpu_high_fg_color '#[fg=red]'
#   set -g @cpu_medium_thresh '30'
#   set -g @cpu_high_thresh '80'
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

# --- Create system stats script ---
$statsScript = @'
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
'@

$statsScriptPath = Join-Path $SCRIPTS_DIR 'system_stats.ps1'
Set-Content -Path $statsScriptPath -Value $statsScript -Force

# --- Set up polling ---
# NOTE: Convert backslashes to forward slashes — psmux strips backslashes
$pollCmd = ("pwsh -NoProfile -File `"$statsScriptPath`"") -replace '\\', '/'
& $PSMUX set-hook -g client-attached "run-shell '$pollCmd'" 2>&1 | Out-Null

# Initial poll
& pwsh -NoProfile -File $statsScriptPath 2>&1 | Out-Null

# --- Prefix + C-c for detailed system info ---
# Create a helper script for the info keybinding.
# Inline pwsh -Command in bind-key breaks due to psmux escaping rules.
$infoScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$c = (Get-CimInstance Win32_Processor).LoadPercentage
$o = Get-CimInstance Win32_OperatingSystem
$m = [math]::Round(($o.TotalVisibleMemorySize - $o.FreePhysicalMemory) / 1MB, 1)
$t = [math]::Round($o.TotalVisibleMemorySize / 1MB, 1)
psmux display-message "CPU: ${c}%  |  RAM: ${m}G / ${t}G"
'@

$infoScriptDir = Join-Path $PSScriptRoot 'scripts'
if (-not (Test-Path $infoScriptDir)) {
    New-Item -ItemType Directory -Path $infoScriptDir -Force | Out-Null
}
$infoScriptPath = Join-Path $infoScriptDir 'cpu_info.ps1'
Set-Content -Path $infoScriptPath -Value $infoScript -Force
$infoPathFwd = $infoScriptPath -replace '\\', '/'

& $PSMUX bind-key C-c "run-shell 'pwsh -NoProfile -File \"$infoPathFwd\"'" 2>&1 | Out-Null

Write-Host "psmux-cpu: loaded (use {cpu} {ram} in status-right)" -ForegroundColor DarkGray
