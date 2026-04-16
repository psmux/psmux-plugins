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

    # Use the saved window name for the initial window
    $newSessionArgs = @("new-session", "-d", "-s", $sessionName, "-c", $firstDir)
    if ($firstWindow.name) {
        $newSessionArgs += @("-n", $firstWindow.name)
    }
    Start-Process -FilePath $PSMUX -ArgumentList $newSessionArgs -WindowStyle Hidden
    Start-Sleep -Seconds 2

    # Get the actual base index used by the new session
    $baseIdx = (& $PSMUX show-options -t $sessionName -gv base-index 2>&1 | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($baseIdx)) { $baseIdx = "0" }
    $baseIdx = [int]$baseIdx
    $firstWinIdx = $baseIdx

    # Create additional panes in first window
    if ($firstWindow.panes.Count -gt 1) {
        for ($p = 1; $p -lt $firstWindow.panes.Count; $p++) {
            $pDir = if ($firstWindow.panes[$p].directory) { $firstWindow.panes[$p].directory } else { $env:USERPROFILE }
            & $PSMUX split-window -t "${sessionName}:${firstWinIdx}" -c $pDir 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500
        }
        # Replay the saved layout so split orientations and sizes match the original.
        if ($firstWindow.layout) {
            & $PSMUX select-layout -t "${sessionName}:${firstWinIdx}" $firstWindow.layout 2>&1 | Out-Null
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

        $winName = if ($win.name) { $win.name } else { $null }
        $newWinArgs = @("-t", $sessionName, "-c", $winDir)
        if ($winName) {
            $newWinArgs = @("-t", $sessionName, "-n", $winName, "-c", $winDir)
        }
        & $PSMUX new-window @newWinArgs 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500

        # Create panes for this window
        if ($win.panes.Count -gt 1) {
            # Get the actual index of the newly created window
            $lastWinIdx = (& $PSMUX list-windows -t $sessionName -F '#{window_index}' 2>&1 | Out-String).Trim() -split "`n" | Select-Object -Last 1
            for ($p = 1; $p -lt $win.panes.Count; $p++) {
                $pDir = if ($win.panes[$p].directory) { $win.panes[$p].directory } else { $env:USERPROFILE }
                & $PSMUX split-window -t "${sessionName}:${lastWinIdx}" -c $pDir 2>&1 | Out-Null
                Start-Sleep -Milliseconds 300
            }
            # Replay the saved layout so split orientations and sizes match the original.
            if ($win.layout) {
                & $PSMUX select-layout -t "${sessionName}:${lastWinIdx}" $win.layout 2>&1 | Out-Null
            }
        }
    }

    # Select the active window
    $activeWin = $session.windows | Where-Object { $_.active -eq $true } | Select-Object -First 1
    if ($activeWin) {
        # Find the matching window by position order, since indices may differ
        $currentWindows = (& $PSMUX list-windows -t $sessionName -F '#{window_index}' 2>&1 | Out-String).Trim() -split "`n"
        $savedWindows = $session.windows
        for ($i = 0; $i -lt $savedWindows.Count; $i++) {
            if ($savedWindows[$i].active -eq $true -and $i -lt $currentWindows.Count) {
                $targetIdx = $currentWindows[$i].Trim()
                & $PSMUX select-window -t "${sessionName}:${targetIdx}" 2>&1 | Out-Null
                break
            }
        }
    }

    Write-Host "  Restored session: $sessionName ($($session.windows.Count) windows)" -ForegroundColor Green
}

& $PSMUX display-message "Environment restored! ($($env_data.sessions.Count) sessions)" 2>&1 | Out-Null
