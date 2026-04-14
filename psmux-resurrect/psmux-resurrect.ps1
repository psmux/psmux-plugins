#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect - Save and restore psmux sessions
# Port of tmux-plugins/tmux-resurrect for psmux
# =============================================================================
#
# Saves and restores the complete psmux environment:
# - All sessions, windows, and pane layouts
# - Working directories for each pane
# - Window names and active pane selections
#
# Key bindings:
#   Prefix + Ctrl-s  - Save environment
#   Prefix + Ctrl-r  - Restore environment
#
# Options (set in ~/.psmux.conf):
#   set -g @resurrect-dir '~/.psmux/resurrect'
#   set -g @resurrect-save-shell-history 'on'
#   set -g @resurrect-capture-pane-contents 'on'
#   set -g @resurrect-strategy-pwsh 'default'
# =============================================================================

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$script:PSMUX = Get-PsmuxBin
$SCRIPTS_DIR = Join-Path $PSScriptRoot 'scripts'
$DEFAULT_RESURRECT_DIR = Join-Path $env:USERPROFILE '.psmux\resurrect'

# Ensure directories exist
foreach ($d in @($SCRIPTS_DIR, $DEFAULT_RESURRECT_DIR)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# --- Create the save script ---
$saveScript = @'
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
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'save.ps1') -Value $saveScript -Force

# --- Create the restore script ---
$restoreScript = @'
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
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'restore.ps1') -Value $restoreScript -Force

# --- Register keybindings ---
$savePath = (Join-Path $SCRIPTS_DIR 'save.ps1') -replace '\\', '/'
$restorePath = (Join-Path $SCRIPTS_DIR 'restore.ps1') -replace '\\', '/'

& $script:PSMUX bind-key C-s "run-shell 'pwsh -NoProfile -File \"$savePath\"'" 2>&1 | Out-Null
& $script:PSMUX bind-key C-r "run-shell 'pwsh -NoProfile -File \"$restorePath\"'" 2>&1 | Out-Null

Write-Host "psmux-resurrect: loaded (Prefix+Ctrl-s=save, Prefix+Ctrl-r=restore)" -ForegroundColor DarkGray
