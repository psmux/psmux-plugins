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
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'restore.ps1') -Value $restoreScript -Force

# --- Register keybindings ---
$savePath = (Join-Path $SCRIPTS_DIR 'save.ps1') -replace '\\', '/'
$restorePath = (Join-Path $SCRIPTS_DIR 'restore.ps1') -replace '\\', '/'

& $script:PSMUX bind-key C-s "run-shell 'pwsh -NoProfile -File \"$savePath\"'" 2>&1 | Out-Null
& $script:PSMUX bind-key C-r "run-shell 'pwsh -NoProfile -File \"$restorePath\"'" 2>&1 | Out-Null

Write-Host "psmux-resurrect: loaded (Prefix+Ctrl-s=save, Prefix+Ctrl-r=restore)" -ForegroundColor DarkGray
