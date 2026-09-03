#!/usr/bin/env pwsh
# psmux-resurrect: Restore saved environment
# Restores: sessions, windows, panes, layouts, active pane per window,
#           zoomed panes, pane titles, running processes (configurable),
#           window flags, active window selection
$ErrorActionPreference = 'Continue'

# psmux refuses `new-session` when PSMUX_SESSION/PSMUX_ACTIVE is set
# (psmux/src/main.rs:627), even with -d which cannot nest a UI. This
# script only issues detached new-session calls, so opt out of the guard
# via the documented override (psmux/src/main.rs:3120). Preserves
# PSMUX_TARGET_SESSION (server routing) and tool-detection signals.
$env:PSMUX_ALLOW_NESTING = '1'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

# --- Progress indicator helpers ---
# A persistent message is exposed via the @resurrect-status user option so
# users can render it in status-right with #{@resurrect-status}. We also
# push the same string via display-message so users without that integration
# still see it as a toast.
#
# NOTE: psmux interprets `display-message -d 0` as "0ms = never show" (the
# guard in server/mod.rs reads `if elapsed < display_time`, so 0 always
# fails). tmux treats 0 as "indefinite"; psmux does not. We use a large
# duration (60s) instead so the toast stays put long enough to outlast a
# normal restore loop; each successive Show-Progress call refreshes it.
$BAR_WIDTH = 14
$PROGRESS_TOAST_MS = 60000
$SUMMARY_TOAST_MS = 5000

function Set-ResurrectStatus([string]$msg) {
    & $PSMUX set-option -g '@resurrect-status' $msg 2>&1 | Out-Null
}

function Clear-ResurrectStatus {
    & $PSMUX set-option -gu '@resurrect-status' 2>&1 | Out-Null
}

function Format-ProgressBar([int]$current, [int]$total) {
    if ($total -le 0) { $total = 1 }
    $filled = [int]([math]::Floor(($current / $total) * $BAR_WIDTH))
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $BAR_WIDTH) { $filled = $BAR_WIDTH }
    $empty = $BAR_WIDTH - $filled
    return ('[' + ('#' * $filled) + ('-' * $empty) + ']')
}

function Show-Progress([int]$current, [int]$total, [string]$sessionName) {
    $bar = Format-ProgressBar -current $current -total $total
    $msg = "psmux-resurrect: restoring $bar $current/$total  $sessionName"
    Set-ResurrectStatus $msg
    & $PSMUX display-message -d $PROGRESS_TOAST_MS $msg 2>&1 | Out-Null
}

# Resolve save directory (support @resurrect-dir option)
$RESURRECT_DIR = Join-Path $env:USERPROFILE '.psmux\resurrect'
try {
    $customDir = (& $PSMUX show-options -gv '@resurrect-dir' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $customDir -and $customDir -ne '' -and $customDir -notmatch 'unknown option|error|no server|not found|refused') {
        $customDir = $customDir -replace '^~', $env:USERPROFILE
        $customDir = $customDir -replace '\$HOME', $env:USERPROFILE
        $RESURRECT_DIR = $customDir
    }
} catch {}
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

try {
    $env_data = Get-Content $saveFile -Raw | ConvertFrom-Json

    # --- Build process restore list ---
    # Default processes to restore (Windows equivalents of tmux defaults)
    $defaultProcesses = @('python','python3','node','npm','ssh','wsl','htop','vim','nvim','less','more','tail')

    # Check user configured process list
    $userProcs = ''
    try {
        $userProcs = (& $PSMUX show-options -gv '@resurrect-processes' 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { $userProcs = '' }
    } catch { $userProcs = '' }
    $restoreProcesses = $true
    $restoreAllProcesses = $false
    $processList = @()

    if ($userProcs -eq 'false') {
        $restoreProcesses = $false
    } elseif ($userProcs -eq ':all:') {
        $restoreAllProcesses = $true
    } elseif ($userProcs -and $userProcs -notmatch 'unknown option|error|no server|not found|refused') {
        # Combine default + user processes
        $processList = $defaultProcesses + ($userProcs -split '\s+' | Where-Object { $_ })
    } else {
        $processList = $defaultProcesses
    }

    function Should-RestoreProcess {
        param([string]$Command)
        if (-not $restoreProcesses) { return $false }
        if ($restoreAllProcesses) { return $true }
        if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
        $cmdBase = ($Command -split '[\\/]' | Select-Object -Last 1) -replace '\.exe$',''
        foreach ($proc in $processList) {
            $procClean = $proc.Trim().Trim('"').Trim("'")
            if ($procClean.StartsWith('~')) {
                # Tilde match: command contains the string anywhere
                $match = $procClean.Substring(1)
                if ($Command -match [regex]::Escape($match)) { return $true }
            } else {
                # Exact base name match
                if ($cmdBase -eq $procClean) { return $true }
            }
        }
        return $false
    }

    # Check @resurrect-overwrite option. By default, existing sessions are
    # preserved and reconciled by restoring only their missing saved windows.
    # When 'on', the whole session is killed and recreated from the save.
    $overwriteExisting = $false
    try {
        $overwriteOpt = (& $PSMUX show-options -gv '@resurrect-overwrite' 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $overwriteOpt -eq 'on') { $overwriteExisting = $true }
    } catch {}

    $totalSessions = $env_data.sessions.Count
    $startTime = Get-Date
    $restoredCount = 0
    $overwrittenCount = 0
    $reusedCount = 0
    $failed = @()
    $totalWindows = 0

    # Return the first whole-line pane id (%N) in $raw, or $null. Match whole
    # lines only: stderr is merged in, so other output can contain a stray %N.
    function Get-PaneId([object]$raw) {
        foreach ($line in @($raw)) {
            $t = "$line".Trim()
            if ($t -match '^%\d+$') { return $t }
        }
        return $null
    }

    function Restore-WindowPanes {
        param($win, [string]$initialPaneId)

        if (-not $initialPaneId) { return }

        $paneIds = @($initialPaneId)
        if ($win.panes.Count -gt 1) {
            for ($p = 1; $p -lt $win.panes.Count; $p++) {
                $pDir = if ($win.panes[$p].directory) { $win.panes[$p].directory } else { $env:USERPROFILE }
                $paneIds += Get-PaneId (& $PSMUX split-window -t $initialPaneId -c $pDir -P -F '#{pane_id}' 2>&1)
            }
        }

        if ($win.layout) {
            & $PSMUX select-layout -t $initialPaneId $win.layout 2>&1 | Out-Null
        }

        $activePaneId = $null
        for ($ti = 0; $ti -lt $win.panes.Count; $ti++) {
            $paneId = $paneIds[$ti]
            if (-not $paneId) { continue }
            $pane = $win.panes[$ti]
            if ($pane.title) {
                & $PSMUX select-pane -t $paneId -T $pane.title 2>&1 | Out-Null
            }
            if ($pane.active -eq $true) { $activePaneId = $paneId }
            if ($restoreProcesses -and $pane.command -and (Should-RestoreProcess $pane.command)) {
                & $PSMUX send-keys -t $paneId $pane.command Enter 2>&1 | Out-Null
                Start-Sleep -Milliseconds 200
            }
        }
        if ($activePaneId) {
            & $PSMUX select-pane -t $activePaneId 2>&1 | Out-Null
        }

        if ($win.zoomed -eq $true -and $win.panes.Count -gt 1 -and $activePaneId) {
            & $PSMUX resize-pane -Z -t $activePaneId 2>&1 | Out-Null
        }

        return $activePaneId
    }

    for ($si = 0; $si -lt $totalSessions; $si++) {
        $session = $env_data.sessions[$si]
        $sessionName = $session.name

        Show-Progress -current ($si + 1) -total $totalSessions -sessionName $sessionName

        # Check if session already exists
        $null = & $PSMUX has-session -t $sessionName 2>&1
        if ($LASTEXITCODE -eq 0) {
            if (-not $overwriteExisting) {
                Write-Host "  Session '$sessionName' already exists, restoring missing windows" -ForegroundColor Yellow

                $existingWindowTargets = @{}
                $windowLines = & $PSMUX list-windows -t $sessionName -F '#{window_index}|#{window_name}' 2>&1
                foreach ($line in @($windowLines)) {
                    $parts = "$line".Trim() -split '\|', 2
                    if ($parts.Count -eq 2 -and $parts[1]) {
                        if (-not $existingWindowTargets.ContainsKey($parts[1])) {
                            $existingWindowTargets[$parts[1]] = @()
                        }
                        $existingWindowTargets[$parts[1]] += "${sessionName}:$($parts[0])"
                    }
                }

                $windowPaneIds = @()
                $windowActivePaneIds = @()
                $matchedWindowCounts = @{}
                $addedWindows = 0
                foreach ($win in @($session.windows)) {
                    $matchedCount = if ($win.name -and $matchedWindowCounts.ContainsKey($win.name)) {
                        $matchedWindowCounts[$win.name]
                    } else {
                        0
                    }
                    if ($win.name -and $existingWindowTargets.ContainsKey($win.name) -and
                        $matchedCount -lt $existingWindowTargets[$win.name].Count) {
                        $windowPaneIds += $existingWindowTargets[$win.name][$matchedCount]
                        $windowActivePaneIds += $null
                        $matchedWindowCounts[$win.name] = $matchedCount + 1
                        continue
                    }

                    $winDir = if ($win.panes -and $win.panes[0].directory) {
                        $win.panes[0].directory
                    } else {
                        $env:USERPROFILE
                    }
                    $newWinArgs = @('-t', $sessionName, '-c', $winDir)
                    if ($win.name) {
                        $newWinArgs = @('-t', $sessionName, '-n', $win.name, '-c', $winDir)
                    }
                    $winPaneId = Get-PaneId (& $PSMUX new-window @newWinArgs -P -F '#{pane_id}' 2>&1)
                    $windowPaneIds += $winPaneId
                    $windowActivePaneIds += (Restore-WindowPanes -win $win -initialPaneId $winPaneId)
                    if ($winPaneId) {
                        $addedWindows++
                    }
                }

                $savedWindows = @($session.windows)
                for ($i = 0; $i -lt $savedWindows.Count; $i++) {
                    if ($savedWindows[$i].active -eq $true) {
                        $activeWindowTarget = $windowPaneIds[$i]
                        if ($activeWindowTarget) {
                            & $PSMUX select-window -t $activeWindowTarget 2>&1 | Out-Null
                            if ($windowActivePaneIds[$i]) {
                                & $PSMUX select-pane -t $windowActivePaneIds[$i] 2>&1 | Out-Null
                            }
                        }
                        break
                    }
                }

                $restoredCount++
                $reusedCount++
                $totalWindows += $addedWindows
                Write-Host "  Reconciled session: $sessionName ($addedWindows missing windows restored)" -ForegroundColor Green
                continue
            }

            Write-Host "  Session '$sessionName' already exists, overwriting (@resurrect-overwrite on)" -ForegroundColor Yellow
            & $PSMUX kill-session -t $sessionName 2>&1 | Out-Null

            # Wait for the kill to land before recreating; a session name that's
            # still tearing down would make the new-session below silently no-op.
            $killed = $false
            for ($k = 0; $k -lt 20; $k++) {
                Start-Sleep -Milliseconds 100
                $null = & $PSMUX has-session -t $sessionName 2>&1
                if ($LASTEXITCODE -ne 0) { $killed = $true; break }
            }
            if (-not $killed) {
                Write-Host "  Failed to kill existing session '$sessionName' for overwrite" -ForegroundColor Red
                $failed += $sessionName
                continue
            }
            $overwrittenCount++
        }

        # Create session with first window
        $firstWindow = $session.windows | Select-Object -First 1
        $firstDir = if ($firstWindow.panes -and $firstWindow.panes[0].directory) {
            $firstWindow.panes[0].directory
        } else {
            $env:USERPROFILE
        }

        # Create the session's first window (named from the save) and capture its pane id.
        $nameArg = if ($firstWindow.name) { @('-n', $firstWindow.name) } else { @() }
        $out = & $PSMUX new-session -d -s $sessionName -c $firstDir @nameArg -P -F '#{pane_id}' 2>&1
        $firstPaneId = Get-PaneId $out

        # Wait for session to be ready
        $ready = $false
        for ($w = 0; $w -lt 40; $w++) {
            Start-Sleep -Milliseconds 250
            $null = & $PSMUX has-session -t $sessionName 2>&1
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        }
        if (-not $ready) {
            Write-Host "  Failed to create session '$sessionName'" -ForegroundColor Red
            $failed += $sessionName
            continue
        }

        # Restore first window
        $windowPaneIds = @($firstPaneId)
        $windowActivePaneIds = @(Restore-WindowPanes -win $firstWindow -initialPaneId $firstPaneId)

        # Create and restore remaining windows
        $remainingWindows = $session.windows | Select-Object -Skip 1
        foreach ($win in $remainingWindows) {
            $winDir = if ($win.panes -and $win.panes[0].directory) {
                $win.panes[0].directory
            } else {
                $env:USERPROFILE
            }

            $newWinArgs = @("-t", $sessionName, "-c", $winDir)
            if ($win.name) {
                $newWinArgs = @("-t", $sessionName, "-n", $win.name, "-c", $winDir)
            }
            $winPaneId = Get-PaneId (& $PSMUX new-window @newWinArgs -P -F '#{pane_id}' 2>&1)
            $windowPaneIds += $winPaneId
            $windowActivePaneIds += (Restore-WindowPanes -win $win -initialPaneId $winPaneId)
        }

        # Select the active window (do this last so it sticks).
        $savedWindows = @($session.windows)
        for ($i = 0; $i -lt $savedWindows.Count; $i++) {
            if ($savedWindows[$i].active -eq $true) {
                if ($i -lt $windowPaneIds.Count -and $windowPaneIds[$i]) {
                    & $PSMUX select-window -t $windowPaneIds[$i] 2>&1 | Out-Null
                    # select-window with a pane-id target also re-activates that
                    # specific pane, which can be the wrong one within this window
                    # (see comment in Restore-WindowPanes). Re-assert the window's
                    # real active pane now that the window itself is selected.
                    if ($i -lt $windowActivePaneIds.Count -and $windowActivePaneIds[$i]) {
                        & $PSMUX select-pane -t $windowActivePaneIds[$i] 2>&1 | Out-Null
                    }
                }
                break
            }
        }

        $restoredCount++
        $totalWindows += $session.windows.Count
        Write-Host "  Restored session: $sessionName ($($session.windows.Count) windows)" -ForegroundColor Green
    }

    $elapsed = ((Get-Date) - $startTime).TotalSeconds
    $elapsedStr = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F1}s", $elapsed)

    $summary = "psmux-resurrect: restored $restoredCount sessions, $totalWindows windows in $elapsedStr"
    if ($overwrittenCount -gt 0) {
        $summary += " ($overwrittenCount overwritten)"
    }
    if ($reusedCount -gt 0) {
        $summary += " ($reusedCount existing sessions reused)"
    }
    if ($failed.Count -gt 0) {
        $summary += " - failed: $($failed -join ', ')"
    }

    Set-ResurrectStatus $summary
    & $PSMUX display-message -d $SUMMARY_TOAST_MS $summary 2>&1 | Out-Null
    & $PSMUX refresh-client -S 2>&1 | Out-Null

    # Keep the persistent status visible for the same window as the toast, then clear
    Start-Sleep -Milliseconds $SUMMARY_TOAST_MS
}
finally {
    Clear-ResurrectStatus
    & $PSMUX refresh-client -S 2>&1 | Out-Null
}
