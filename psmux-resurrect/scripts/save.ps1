#!/usr/bin/env pwsh
# psmux-resurrect: Save current environment
$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin
$RESURRECT_DIR = Join-Path $env:USERPROFILE '.psmux\resurrect'
if (-not (Test-Path $RESURRECT_DIR)) {
    New-Item -ItemType Directory -Path $RESURRECT_DIR -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$saveFile = Join-Path $RESURRECT_DIR "psmux_resurrect_$timestamp.json"
$lastFile = Join-Path $RESURRECT_DIR 'last'

& $PSMUX display-message "Saving psmux environment..." 2>&1 | Out-Null

$env_data = @{
    timestamp = $timestamp
    sessions = @()
}

# Get all session names using format flag for clean parsing
$sessionLines = (& $PSMUX ls -F '#{session_name}' 2>&1) | Out-String
foreach ($line in ($sessionLines -split "`n")) {
    $sessionName = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($sessionName)) { continue }

    $sessionData = @{
        name = $sessionName
        windows = @()
    }

    # Get windows using format flags for reliable parsing (no flag chars like *)
    $windowLines = (& $PSMUX list-windows -t $sessionName -F '#{window_index}|#{window_name}|#{window_active}|#{window_layout}' 2>&1) | Out-String
    foreach ($wline in ($windowLines -split "`n")) {
        $wline = $wline.Trim()
        if ([string]::IsNullOrWhiteSpace($wline)) { continue }

        $parts = $wline -split '\|', 4
        if ($parts.Count -lt 4) { continue }

        $winIndex = $parts[0]
        $winName = $parts[1]
        $winActive = $parts[2]
        $winLayout = $parts[3]

        $windowData = @{
            index = [int]$winIndex
            name = $winName
            layout = $winLayout
            active = ($winActive -eq '1')
            panes = @()
        }

        # Get panes using format flags for reliable parsing
        $paneLines = (& $PSMUX list-panes -t "${sessionName}:${winIndex}" -F '#{pane_index}|#{pane_current_path}' 2>&1) | Out-String
        foreach ($pline in ($paneLines -split "`n")) {
            $pline = $pline.Trim()
            if ([string]::IsNullOrWhiteSpace($pline)) { continue }

            $pParts = $pline -split '\|', 2
            $paneIdx = if ($pParts.Count -ge 1) { [int]$pParts[0] } else { 0 }
            $paneDir = if ($pParts.Count -ge 2 -and $pParts[1]) { $pParts[1] } else { $env:USERPROFILE }

            $paneData = @{
                index = $paneIdx
                directory = $paneDir
            }

            # Capture pane contents if enabled
            $captureContents = (& $PSMUX show-options -gv '@resurrect-capture-pane-contents' 2>&1 | Out-String).Trim()
            if ($captureContents -eq 'on') {
                $paneTarget = "${sessionName}:${winIndex}.${paneIdx}"
                & $PSMUX capture-pane -t $paneTarget -p 2>&1 | Out-Null
                $paneContent = (& $PSMUX show-buffer 2>&1 | Out-String)
                $paneData['content'] = $paneContent
            }

            $windowData.panes += $paneData
        }

        $sessionData.windows += $windowData
    }

    $env_data.sessions += $sessionData
}

# Save to JSON
$env_data | ConvertTo-Json -Depth 10 | Set-Content -Path $saveFile -Encoding UTF8 -Force

# Update 'last' pointer
$saveFile | Set-Content -Path $lastFile -Encoding UTF8 -Force

& $PSMUX display-message "Environment saved! ($($env_data.sessions.Count) sessions)" 2>&1 | Out-Null
Write-Host "psmux-resurrect: Saved to $saveFile" -ForegroundColor Green
