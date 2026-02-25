#!/usr/bin/env pwsh
# psmux-resurrect: Restore saved environment
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
$lastFile = Join-Path $RESURRECT_DIR 'last'

if (-not (Test-Path $lastFile)) {
    & $PSMUX display-message "No saved environment found!" 2>&1 | Out-Null
    Write-Host "psmux-resurrect: No save file found" -ForegroundColor Red
    exit 1
}

$saveFile = (Get-Content $lastFile -Raw).Trim()
if (-not (Test-Path $saveFile)) {
    & $PSMUX display-message "Save file not found: $saveFile" 2>&1 | Out-Null
    exit 1
}

& $PSMUX display-message "Restoring psmux environment..." 2>&1 | Out-Null

$env_data = Get-Content $saveFile -Raw | ConvertFrom-Json

foreach ($session in $env_data.sessions) {
    $sessionName = $session.name

    # Check if session already exists
    $exists = & $PSMUX has-session -t $sessionName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Session '$sessionName' already exists, skipping" -ForegroundColor Yellow
        continue
    }

    # Create session with first window
    $firstWindow = $session.windows | Select-Object -First 1
    $firstDir = if ($firstWindow.panes -and $firstWindow.panes[0].directory) {
        $firstWindow.panes[0].directory
    } else {
        $env:USERPROFILE
    }

    Start-Process -FilePath $PSMUX -ArgumentList "new-session", "-d", "-s", $sessionName, "-c", $firstDir -WindowStyle Hidden
    Start-Sleep -Seconds 2

    # Rename first window
    if ($firstWindow.name) {
        & $PSMUX rename-window -t "${sessionName}:1" $firstWindow.name 2>&1 | Out-Null
    }

    # Create additional panes in first window
    if ($firstWindow.panes.Count -gt 1) {
        for ($p = 1; $p -lt $firstWindow.panes.Count; $p++) {
            $pDir = $firstWindow.panes[$p].directory
            & $PSMUX split-window -t $sessionName -c $pDir 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500
        }
    }

    # Create remaining windows
    $remainingWindows = $session.windows | Select-Object -Skip 1
    foreach ($win in $remainingWindows) {
        $winDir = if ($win.panes -and $win.panes[0].directory) {
            $win.panes[0].directory
        } else {
            $env:USERPROFILE
        }

        & $PSMUX new-window -t $sessionName -n $win.name -c $winDir 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500

        # Create panes for this window
        if ($win.panes.Count -gt 1) {
            for ($p = 1; $p -lt $win.panes.Count; $p++) {
                $pDir = $win.panes[$p].directory
                & $PSMUX split-window -t $sessionName -c $pDir 2>&1 | Out-Null
                Start-Sleep -Milliseconds 300
            }
        }
    }

    # Select the active window
    $activeWin = $session.windows | Where-Object { $_.active -eq $true } | Select-Object -First 1
    if ($activeWin) {
        & $PSMUX select-window -t "${sessionName}:$($activeWin.index)" 2>&1 | Out-Null
    }

    Write-Host "  Restored session: $sessionName ($($session.windows.Count) windows)" -ForegroundColor Green
}

& $PSMUX display-message "Environment restored! ($($env_data.sessions.Count) sessions)" 2>&1 | Out-Null
