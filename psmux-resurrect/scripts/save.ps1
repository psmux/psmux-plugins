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
$PLUGIN_DIR = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'save_strategy.ps1')

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

function Get-PaneListing([string]$sessionName, [string]$format) {
    # Read raw UTF-8 stdout: PowerShell's native line handling can remove CR
    # or supply a newline that conceals a truncated escape sequence.
    $arguments = @('list-panes', '-s', '-t', $sessionName, '-F', $format)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PSMUX
    if ([IO.Path]::GetExtension($PSMUX) -eq '.ps1') {
        $startInfo.FileName = (Get-Command pwsh -CommandType Application -ErrorAction Stop).Source
        $literals = @($PSMUX) + $arguments | ForEach-Object {
            "'{0}'" -f [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($_)
        }
        $invocation = '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); & ' + ($literals -join ' ')
        $arguments = @('-NoProfile', '-Command', $invocation)
    }
    foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or -not $text.Trim()) {
            throw "list-panes for '$sessionName' failed or returned no panes: $text$errorText"
        }
        return $text
    } finally { $process.Dispose() }
}

function Read-CaptureRows([string]$listing) {
    # Decode #{q:...} before treating unescaped tabs and LF as separators.
    # psmux emits LF records; its q modifier does not escape CR, so reject CR.
    $field = [Text.StringBuilder]::new()
    $fields = [Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $listing.Length; $i++) {
        $ch = $listing[$i]
        if ($ch -eq '\') {
            if (++$i -eq $listing.Length) { throw 'Incomplete quoted pane data.' }
            if ($listing[$i] -eq "`r") { throw 'Carriage return in quoted pane data.' }
            [void]$field.Append($listing[$i])
        } elseif ($ch -eq "`t" -or $ch -eq "`n") {
            $fields.Add($field.ToString())
            [void]$field.Clear()
            if ($ch -eq "`n") {
                if ($fields.Count -gt 1 -or $fields[0]) { @{ Fields = $fields.ToArray() } }
                $fields.Clear()
            }
        } elseif ($ch -eq "`r") {
            throw 'Unescaped carriage return in pane data.'
        } else { [void]$field.Append($ch) }
    }
    if ($field.Length -gt 0 -or $fields.Count -gt 0) { throw 'Unterminated pane record.' }
}

function Get-EnvironmentCapture {
    $sessions = @()
    $skipped = @()
    $commands = @()
    $sessionLines = (& $PSMUX list-sessions -F '#{session_name}' 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $sessionLines.Trim()) {
        throw "list-sessions failed or returned no sessions: $($sessionLines.Trim())"
    }

    # Quoting keeps user text from introducing field or record separators.
    $paneFmt = (@(
        'window_index', 'window_name', 'window_active', 'window_layout',
        'window_zoomed_flag', 'window_flags', 'pane_index', 'pane_current_path',
        'pane_active', 'pane_title', 'pane_pid', 'pane_current_command'
    ) | ForEach-Object { '#{{q:{0}}}' -f $_ }) -join "`t"
    foreach ($line in ($sessionLines -split "`r?`n")) {
        $sessionName = $line.Trim()
        if (-not $sessionName) { continue }
        if ($sessionName.StartsWith('__')) {
            $skipped += "$sessionName (internal)"
            continue
        }
        $isAutoNamed = Test-AutoNamedSession $sessionName
        if ($isAutoNamed -and $saveUnnamed -eq 'off') {
            $skipped += "$sessionName (unnamed)"
            continue
        }

        $paneLines = Get-PaneListing $sessionName $paneFmt
        $sessionData = @{ name = $sessionName; windows = @() }
        $windows = @{}
        $sessionCommands = @()
        foreach ($row in (Read-CaptureRows $paneLines)) {
            $parts = $row.Fields
            $winIndex = 0; $paneIndex = 0
            if ($parts.Count -ne 12 -or
                -not [int]::TryParse($parts[0], [ref]$winIndex) -or $winIndex -lt 0 -or
                -not [int]::TryParse($parts[6], [ref]$paneIndex) -or $paneIndex -lt 0 -or
                $parts[2] -notmatch '^[01]$' -or $parts[4] -notmatch '^[01]$' -or
                $parts[8] -notmatch '^[01]$' -or -not $parts[3] -or
                $parts[10] -notmatch '^\d*$') {
                throw "Invalid pane data for '$sessionName'."
            }
            if (-not $windows.ContainsKey($winIndex)) {
                $windows[$winIndex] = @{
                    index = $winIndex; name = $parts[1]; active = ($parts[2] -eq '1')
                    layout = $parts[3]; zoomed = ($parts[4] -eq '1'); flags = $parts[5]; panes = @()
                }
                $sessionData.windows += $windows[$winIndex]
            }
            $paneData = @{
                index = $paneIndex
                directory = if ($parts[7]) { $parts[7] } else { $env:USERPROFILE }
                active = ($parts[8] -eq '1'); title = $parts[9]; command = $parts[11]
            }
            $windows[$winIndex].panes += $paneData
            $sessionCommands += @{ Pane = $paneData; Pid = $parts[10]; Target = "${sessionName}:${winIndex}.${paneIndex}" }
        }
        if ($isAutoNamed -and $saveUnnamed -eq 'auto' -and (Test-UntouchedSession $sessionData)) {
            $skipped += "$sessionName (unnamed, untouched)"
            continue
        }
        $sessions += $sessionData
        $commands += $sessionCommands
    }
    return @{ Sessions = $sessions; Skipped = $skipped; Commands = $commands }
}

$capture = $null
$retryDelays = @(2, 4, 6)
for ($attempt = 0; $attempt -le $retryDelays.Count; $attempt++) {
    try {
        $capture = Get-EnvironmentCapture
        break
    } catch {
        $captureError = $_.Exception.Message
        if ($attempt -eq $retryDelays.Count) {
            Write-Host "psmux-resurrect: Save failed after 4 attempts; previous snapshot preserved. $captureError" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "psmux-resurrect: Capture failed, retrying in $($retryDelays[$attempt]) seconds. $captureError" -ForegroundColor DarkGray
        Start-Sleep -Seconds $retryDelays[$attempt]
    }
}
$env_data.sessions = $capture.Sessions
$skippedSessions = $capture.Skipped

# Strategies run only for included panes after the complete capture succeeds.
# Their failures preserve the original command and do not retry the capture.
foreach ($entry in $capture.Commands) {
    $pane = $entry.Pane
    $pane.command = Get-SaveCommand -PaneCommand $pane.command -PanePid $entry.Pid `
        -Directory $pane.directory -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR
    if ($captureEnabled) {
        $paneContent = (& $PSMUX capture-pane -t $entry.Target -p 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $paneContent) { $pane['content'] = $paneContent }
    }
}

if ($skippedSessions.Count -gt 0) {
    Write-Host "psmux-resurrect: not saving $($skippedSessions -join ', ')" -ForegroundColor DarkGray
}

# Preserve the previous snapshot when policy excludes every running session.
if (@($env_data.sessions).Count -eq 0) {
    & $PSMUX display-message "Nothing to save: only unnamed or internal sessions are running (see @resurrect-save-unnamed)." 2>&1 | Out-Null
    Write-Host "psmux-resurrect: nothing to save, every running session was skipped (set @resurrect-save-unnamed 'on' to keep unnamed sessions)." -ForegroundColor Yellow
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
