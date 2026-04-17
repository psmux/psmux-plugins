#!/usr/bin/env pwsh
# psmux-resurrect: Save current environment
# Captures: sessions, windows, panes, layouts, active pane, zoomed state,
#           pane titles, pane current command, window flags, pane contents (opt)
$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

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
if (-not (Test-Path $RESURRECT_DIR)) {
    New-Item -ItemType Directory -Path $RESURRECT_DIR -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$saveFile = Join-Path $RESURRECT_DIR "psmux_resurrect_$timestamp.json"
$lastFile = Join-Path $RESURRECT_DIR 'last'

& $PSMUX display-message "Saving psmux environment..." 2>&1 | Out-Null

# Check if pane contents capture is enabled (query once, not per pane)
$captureEnabled = $false
try {
    $captureContents = (& $PSMUX show-options -gv '@resurrect-capture-pane-contents' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $captureContents -eq 'on') { $captureEnabled = $true }
} catch {}

$env_data = @{
    version   = 2
    timestamp = $timestamp
    sessions  = @()
}

# Get all session names using format flag for clean parsing (retry on empty)
$sessionLines = ''
for ($retry = 0; $retry -lt 5; $retry++) {
    $sessionLines = (& $PSMUX list-sessions -F '#{session_name}' 2>&1) | Out-String
    if ($sessionLines.Trim()) { break }
    Start-Sleep -Milliseconds 500
}
foreach ($line in ($sessionLines -split "`n")) {
    $sessionName = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($sessionName)) { continue }

    $sessionData = @{
        name    = $sessionName
        windows = @()
    }

    # Get windows: index, name, active, layout, zoomed flag, flags
    $winFmt = '#{window_index}|#{window_name}|#{window_active}|#{window_layout}|#{window_zoomed_flag}|#{window_flags}'
    $windowLines = (& $PSMUX list-windows -t $sessionName -F $winFmt 2>&1) | Out-String
    foreach ($wline in ($windowLines -split "`n")) {
        $wline = $wline.Trim()
        if ([string]::IsNullOrWhiteSpace($wline)) { continue }

        $parts = $wline -split '\|', 6
        if ($parts.Count -lt 4) { continue }

        $winIndex  = $parts[0]
        $winName   = $parts[1]
        $winActive = $parts[2]
        $winLayout = $parts[3]
        $winZoomed = if ($parts.Count -ge 5) { $parts[4] } else { '0' }
        $winFlags  = if ($parts.Count -ge 6) { $parts[5] } else { '' }

        $windowData = @{
            index  = [int]$winIndex
            name   = $winName
            layout = $winLayout
            active = ($winActive -eq '1')
            zoomed = ($winZoomed -eq '1')
            flags  = $winFlags
            panes  = @()
        }

        # Get panes: index, path, active, title, current_command
        $paneFmt = '#{pane_index}|#{pane_current_path}|#{pane_active}|#{pane_title}|#{pane_current_command}'
        $paneLines = (& $PSMUX list-panes -t "${sessionName}:${winIndex}" -F $paneFmt 2>&1) | Out-String
        foreach ($pline in ($paneLines -split "`n")) {
            $pline = $pline.Trim()
            if ([string]::IsNullOrWhiteSpace($pline)) { continue }

            $pParts = $pline -split '\|', 5
            $paneIdx  = if ($pParts.Count -ge 1) { [int]$pParts[0] } else { 0 }
            $paneDir  = if ($pParts.Count -ge 2 -and $pParts[1]) { $pParts[1] } else { $env:USERPROFILE }
            $paneAct  = if ($pParts.Count -ge 3) { $pParts[2] } else { '0' }
            $paneTtl  = if ($pParts.Count -ge 4) { $pParts[3] } else { '' }
            $paneCmd  = if ($pParts.Count -ge 5) { $pParts[4] } else { '' }

            $paneData = @{
                index     = $paneIdx
                directory = $paneDir
                active    = ($paneAct -eq '1')
                title     = $paneTtl
                command   = $paneCmd
            }

            # Capture pane contents if enabled
            if ($captureEnabled) {
                $paneTarget = "${sessionName}:${winIndex}.${paneIdx}"
                $paneContent = (& $PSMUX capture-pane -t $paneTarget -p 2>&1 | Out-String)
                if ($paneContent) {
                    $paneData['content'] = $paneContent
                }
            }

            $windowData.panes += $paneData
        }

        $sessionData.windows += $windowData
    }

    $env_data.sessions += $sessionData
}

# Save to JSON
$jsonContent = $env_data | ConvertTo-Json -Depth 10

# Deduplication: only write if content differs from last save
# Build a stable fingerprint from session structure (avoids JSON key ordering issues)
function Get-SessionFingerprint($data) {
    $parts = @()
    foreach ($s in ($data.sessions | Sort-Object { $_.name })) {
        $sp = @("S:$($s.name)")
        foreach ($w in ($s.windows | Sort-Object { $_.index })) {
            $wp = "W:$($w.index)|$($w.name)|$($w.active)|$($w.layout)|$($w.zoomed)|$($w.flags)"
            $sp += $wp
            foreach ($p in ($w.panes | Sort-Object { $_.index })) {
                $sp += "P:$($p.index)|$($p.directory)|$($p.active)|$($p.title)|$($p.command)"
            }
        }
        $parts += ($sp -join ';')
    }
    return ($parts -join '||')
}

$shouldWrite = $true
if (Test-Path $lastFile) {
    $lastPath = (Get-Content $lastFile -Raw -ErrorAction SilentlyContinue)
    if ($lastPath) {
        $lastPath = $lastPath.Trim()
        if (Test-Path $lastPath) {
            $lastContent = Get-Content $lastPath -Raw -ErrorAction SilentlyContinue
            if ($lastContent) {
                $lastObj = $lastContent | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($lastObj -and $lastObj.sessions) {
                    $currFP = Get-SessionFingerprint $env_data
                    $lastFP = Get-SessionFingerprint $lastObj
                    if ($currFP -eq $lastFP) {
                        $shouldWrite = $false
                    }
                }
            }
        }
    }
}

if ($shouldWrite) {
    $jsonContent | Set-Content -Path $saveFile -Encoding UTF8 -Force
    $saveFile | Set-Content -Path $lastFile -Encoding UTF8 -Force

    # Backup rotation: keep at most 20 saves, delete oldest beyond that
    $maxBackups = 20
    $allSaves = Get-ChildItem -Path $RESURRECT_DIR -Filter 'psmux_resurrect_*.json' | Sort-Object Name -Descending
    if ($allSaves.Count -gt $maxBackups) {
        $toDelete = $allSaves | Select-Object -Skip $maxBackups
        foreach ($old in $toDelete) {
            Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    & $PSMUX display-message "Environment saved! ($($env_data.sessions.Count) sessions)" 2>&1 | Out-Null
    Write-Host "psmux-resurrect: Saved to $saveFile" -ForegroundColor Green
} else {
    # No changes, skip writing a duplicate
    & $PSMUX display-message "Environment unchanged, skipping save." 2>&1 | Out-Null
    Write-Host "psmux-resurrect: No changes detected, skipped." -ForegroundColor DarkGray
}
