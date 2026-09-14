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

# --- Unnamed session policy (@resurrect-save-unnamed) ---------------------
# A bare `psmux` names its session with the next free number (0, 1, 2 ...).
# Persisting those makes them permanent: restore recreates them, the next
# save re-persists them, and there is no way out of the loop by editing the
# save files (issue #37). tmux-resurrect saves them regardless, but on
# Windows a bare launch is the common entry point and the server outlives
# the terminal window, so stray numbered sessions pile up much faster.
#
#   auto (default)  save an auto-named session only once it has been shaped:
#                   a second window or pane, or a program other than an idle
#                   shell in its pane. An untouched one is exactly what the
#                   next bare launch gives you anyway, so it is skipped.
#   on              save every auto-named session (tmux-resurrect parity).
#   off             never save auto-named sessions.
#
# Internal sessions (names starting with __, e.g. the __warm__ standby) are
# never saved whatever the setting.
$saveUnnamed = 'auto'
try {
    $unnamedOpt = (& $PSMUX show-options -gv '@resurrect-save-unnamed' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $unnamedOpt -match '^(on|off|auto)$') { $saveUnnamed = $unnamedOpt }
} catch {}

$idleShells = @('pwsh','powershell','cmd','bash','sh','zsh','fish','nu','elvish','xonsh','shell')

function Test-AutoNamedSession([string]$name) {
    return ($name -match '^\d+$')
}

# True when the session still has the shape a bare launch gives it: one
# window, one pane, nothing but an idle shell running.
function Test-UntouchedSession($sessionData) {
    if (@($sessionData.windows).Count -ne 1) { return $false }
    $w = $sessionData.windows[0]
    if (@($w.panes).Count -ne 1) { return $false }
    $cmd = "$($w.panes[0].command)".Trim()
    if (-not $cmd) { return $true }
    $base = ($cmd -split '\s+', 2)[0]
    $base = ($base -split '[\\/]' | Select-Object -Last 1) -replace '\.exe$', ''
    return ($idleShells -contains $base.ToLowerInvariant())
}

$skippedSessions = @()

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

    # Cheap name-based exclusions first, before any per-window queries.
    if ($sessionName.StartsWith('__')) {
        $skippedSessions += "$sessionName (internal)"
        continue
    }
    $isAutoNamed = Test-AutoNamedSession $sessionName
    if ($isAutoNamed -and $saveUnnamed -eq 'off') {
        $skippedSessions += "$sessionName (unnamed)"
        continue
    }

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

    # The shape check needs the windows and panes gathered above.
    if ($isAutoNamed -and $saveUnnamed -eq 'auto' -and (Test-UntouchedSession $sessionData)) {
        $skippedSessions += "$sessionName (unnamed, untouched)"
        continue
    }

    $env_data.sessions += $sessionData
}

if ($skippedSessions.Count -gt 0) {
    Write-Host "psmux-resurrect: not saving $($skippedSessions -join ', ')" -ForegroundColor DarkGray
}

# Guard: never persist a 0-session snapshot.
# psmux returns exit 0 with empty output when no server is running (which is also why the
# capture loop above retries on empty), so a 0-session capture almost always means "the
# server is down", not "the user has no sessions" -- tmux/psmux tears the server down when
# its last session goes. Writing it would create a useless restore point AND repoint 'last'
# to it; the 20-slot rotation then evicts the good snapshots, silently destroying the
# ability to resurrect. We bail here -- after the capture loop but before dedup, the write
# and the 'last' repoint -- so an empty capture has no side effects.
# (Known limitation: a PARTIAL capture -- a session reported mid-startup with incomplete
# windows/panes -- has >=1 session, so it passes this guard and is still written. Closing
# that needs an expected-session-count signal we don't have here; tracked as a follow-up.)
if (@($env_data.sessions).Count -eq 0) {
    if ($skippedSessions.Count -gt 0) {
        # Sessions exist but every one of them was filtered out above. Say so
        # explicitly: this is the unnamed policy at work, not a dead server.
        & $PSMUX display-message "Nothing to save: only unnamed or internal sessions are running (see @resurrect-save-unnamed)." 2>&1 | Out-Null
        Write-Host "psmux-resurrect: nothing to save, every running session was skipped (set @resurrect-save-unnamed 'on' to keep unnamed sessions)." -ForegroundColor Yellow
        exit 0
    }
    & $PSMUX display-message "No sessions to save, skipping." 2>&1 | Out-Null
    Write-Host "psmux-resurrect: No sessions captured, skipping save (server likely down)." -ForegroundColor Yellow
    exit 0
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

    $savedMsg = "Environment saved! ($($env_data.sessions.Count) sessions"
    if ($skippedSessions.Count -gt 0) { $savedMsg += ", $($skippedSessions.Count) skipped" }
    $savedMsg += ")"
    & $PSMUX display-message $savedMsg 2>&1 | Out-Null
    Write-Host "psmux-resurrect: Saved to $saveFile" -ForegroundColor Green
} else {
    # No changes, skip writing a duplicate
    & $PSMUX display-message "Environment unchanged, skipping save." 2>&1 | Out-Null
    Write-Host "psmux-resurrect: No changes detected, skipped." -ForegroundColor DarkGray
}
