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

# Get all sessions
$sessions = (& $PSMUX ls 2>&1) | Out-String
foreach ($line in ($sessions -split "`n")) {
    if ($line -match '^(\S+):') {
        $sessionName = $Matches[1]
        $sessionData = @{
            name = $sessionName
            windows = @()
        }

        # Get windows for this session
        $windows = (& $PSMUX list-windows -t $sessionName 2>&1) | Out-String
        foreach ($wline in ($windows -split "`n")) {
            if ($wline -match '^(\d+):\s+(\S+)') {
                $winIndex = $Matches[1]
                $winName = $Matches[2]
                $windowData = @{
                    index = [int]$winIndex
                    name = $winName
                    panes = @()
                }

                # Get panes for this window
                $panes = (& $PSMUX list-panes -t "${sessionName}:${winIndex}" 2>&1) | Out-String
                $paneIndex = 0
                foreach ($pline in ($panes -split "`n")) {
                    if ($pline -match '^\d+:') {
                        # Try to get pane working directory
                        $paneTarget = "${sessionName}:${winIndex}.${paneIndex}"
                        $paneDir = (& $PSMUX display-message -t $paneTarget -p '#{pane_current_path}' 2>&1 | Out-String).Trim()

                        $paneData = @{
                            index = $paneIndex
                            directory = if ($paneDir) { $paneDir } else { $env:USERPROFILE }
                        }

                        # Capture pane contents if enabled
                        $captureContents = (& $PSMUX show-options -g -v '@resurrect-capture-pane-contents' 2>&1 | Out-String).Trim()
                        if ($captureContents -eq 'on') {
                            & $PSMUX capture-pane -t $paneTarget -J 2>&1 | Out-Null
                            $paneContent = (& $PSMUX show-buffer 2>&1 | Out-String)
                            $paneData['content'] = $paneContent
                        }

                        $windowData.panes += $paneData
                        $paneIndex++
                    }
                }

                # Determine layout
                $layout = (& $PSMUX display-message -t "${sessionName}:${winIndex}" -p '#{window_layout}' 2>&1 | Out-String).Trim()
                $windowData['layout'] = $layout

                # Is this the active window?
                $activeFlag = (& $PSMUX display-message -t "${sessionName}:${winIndex}" -p '#{window_active}' 2>&1 | Out-String).Trim()
                $windowData['active'] = ($activeFlag -eq '1')

                $sessionData.windows += $windowData
            }
        }

        $env_data.sessions += $sessionData
    }
}

# Save to JSON
$env_data | ConvertTo-Json -Depth 10 | Set-Content -Path $saveFile -Encoding UTF8 -Force

# Update 'last' pointer
$saveFile | Set-Content -Path $lastFile -Encoding UTF8 -Force

& $PSMUX display-message "Environment saved! ($($env_data.sessions.Count) sessions)" 2>&1 | Out-Null
Write-Host "psmux-resurrect: Saved to $saveFile" -ForegroundColor Green
