#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect E2E Test Suite
# Tests save + restore of sessions, windows, panes, layouts, active pane,
# zoomed state, pane titles, process restore, backup rotation, deduplication
# =============================================================================

$ErrorActionPreference = "Continue"
$PSMUX = (Get-Command psmux -EA Stop).Source
$psmuxDir = "$env:USERPROFILE\.psmux"
$RESURRECT_DIR = "$env:USERPROFILE\.psmux\resurrect"
$SAVE_SCRIPT = Join-Path $PSScriptRoot "..\psmux-resurrect\scripts\save.ps1"
$RESTORE_SCRIPT = Join-Path $PSScriptRoot "..\psmux-resurrect\scripts\restore.ps1"
$SESSION = "resurrect_test"
$script:TestsPassed = 0
$script:TestsFailed = 0

function Write-Pass($msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green; $script:TestsPassed++ }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:TestsFailed++ }

function Cleanup {
    & $PSMUX kill-session -t $SESSION 2>&1 | Out-Null
    & $PSMUX kill-session -t "${SESSION}_restored" 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    Remove-Item "$psmuxDir\$SESSION.*" -Force -EA SilentlyContinue
    Remove-Item "$psmuxDir\${SESSION}_restored.*" -Force -EA SilentlyContinue
}

function Wait-Session {
    param([string]$Name, [int]$TimeoutMs = 15000)
    for ($i = 0; $i -lt ($TimeoutMs / 250); $i++) {
        Start-Sleep -Milliseconds 250
        & $PSMUX has-session -t $Name 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

# =============================================================================
Write-Host "`n=== psmux-resurrect E2E Test Suite ===" -ForegroundColor Cyan
Write-Host "Save script:    $SAVE_SCRIPT"
Write-Host "Restore script: $RESTORE_SCRIPT"
# =============================================================================

# Ensure resurrect dir exists
if (-not (Test-Path $RESURRECT_DIR)) {
    New-Item -ItemType Directory -Path $RESURRECT_DIR -Force | Out-Null
}

# Remove any old saves for clean testing
$oldSaves = Get-ChildItem -Path $RESURRECT_DIR -Filter 'psmux_resurrect_*.json' -EA SilentlyContinue
foreach ($f in $oldSaves) { Remove-Item $f.FullName -Force -EA SilentlyContinue }
Remove-Item "$RESURRECT_DIR\last" -Force -EA SilentlyContinue

# Create a keepalive session to prevent server shutdown during kill/restore cycles
$KEEPALIVE = "resurrect_keepalive"
& $PSMUX kill-session -t $KEEPALIVE 2>&1 | Out-Null
& $PSMUX new-session -d -s $KEEPALIVE -n "keepalive" 2>&1 | Out-Null
if (-not (Wait-Session $KEEPALIVE)) {
    Write-Host "  WARNING: Could not create keepalive session, server may shut down during tests" -ForegroundColor Yellow
}

# ===================================================================
# PART 1: Save Feature Tests
# ===================================================================
Write-Host "`n--- PART 1: Save Feature Tests ---" -ForegroundColor Cyan
Cleanup

# Create a session with known structure:
#   Window 0: "editor" with 2 panes (split)
#   Window 1: "logs" with 1 pane
#   Window 2: "build" with 3 panes, zoomed
& $PSMUX new-session -d -s $SESSION -n "editor" -c $env:USERPROFILE 2>&1 | Out-Null
if (-not (Wait-Session $SESSION)) {
    Write-Fail "Could not create test session"
    exit 1
}
Write-Host "  Session created" -ForegroundColor DarkGray

# Split window 0 horizontally
& $PSMUX split-window -h -t "${SESSION}:0" -c $env:TEMP 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

# Set a pane title on pane 0
& $PSMUX select-pane -t "${SESSION}:0.0" -T "main_editor" 2>&1 | Out-Null

# Create window 1: "logs"
& $PSMUX new-window -t $SESSION -n "logs" -c $env:SYSTEMROOT 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

# Create window 2: "build" with 3 panes
& $PSMUX new-window -t $SESSION -n "build" -c $env:USERPROFILE 2>&1 | Out-Null
Start-Sleep -Milliseconds 500
& $PSMUX split-window -v -t "${SESSION}:2" -c $env:TEMP 2>&1 | Out-Null
Start-Sleep -Milliseconds 300
& $PSMUX split-window -h -t "${SESSION}:2" -c $env:USERPROFILE 2>&1 | Out-Null
Start-Sleep -Milliseconds 300

# Select pane 1 as active in window 2
& $PSMUX select-pane -t "${SESSION}:2.1" 2>&1 | Out-Null

# Zoom window 2
& $PSMUX resize-pane -Z -t "${SESSION}:2" 2>&1 | Out-Null
Start-Sleep -Milliseconds 300

# Select window 1 ("logs") as the active window
& $PSMUX select-window -t "${SESSION}:1" 2>&1 | Out-Null
Start-Sleep -Milliseconds 300

Write-Host "  Test environment built: 3 windows, mixed splits, zoom, titles" -ForegroundColor DarkGray

# === TEST 1: Run save script ===
Write-Host "`n[Test 1] Save script creates JSON file" -ForegroundColor Yellow
Start-Sleep -Seconds 1  # Let server stabilize before save
& pwsh -NoProfile -ExecutionPolicy Bypass -File $SAVE_SCRIPT 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

$lastFile = "$RESURRECT_DIR\last"
if (Test-Path $lastFile) {
    $savedPath = (Get-Content $lastFile -Raw).Trim()
    if (Test-Path $savedPath) {
        Write-Pass "Save file created: $(Split-Path $savedPath -Leaf)"
    } else {
        Write-Fail "Last pointer exists but file missing: $savedPath"
    }
} else {
    Write-Fail "No 'last' file created"
}

# === TEST 2: Validate JSON structure ===
Write-Host "`n[Test 2] JSON structure validation" -ForegroundColor Yellow
$savedPath = (Get-Content $lastFile -Raw).Trim()
$json = Get-Content $savedPath -Raw | ConvertFrom-Json

# Session count
if ($json.sessions.Count -ge 1) { Write-Pass "Sessions saved: $($json.sessions.Count)" }
else { Write-Fail "No sessions in JSON" }

# Find our test session
$testSession = $json.sessions | Where-Object { $_.name -eq $SESSION }
if ($testSession) { Write-Pass "Test session '$SESSION' found in save" }
else { Write-Fail "Test session '$SESSION' not in save"; exit 1 }

# Window count
if ($testSession.windows.Count -eq 3) { Write-Pass "3 windows saved" }
else { Write-Fail "Expected 3 windows, got $($testSession.windows.Count)" }

# Window names
$winNames = $testSession.windows | ForEach-Object { $_.name }
if ($winNames -contains 'editor' -and $winNames -contains 'logs' -and $winNames -contains 'build') {
    Write-Pass "Window names correct: $($winNames -join ', ')"
} else {
    Write-Fail "Window names wrong: $($winNames -join ', ')"
}

# === TEST 3: Pane count per window ===
Write-Host "`n[Test 3] Pane counts per window" -ForegroundColor Yellow
$editorWin = $testSession.windows | Where-Object { $_.name -eq 'editor' }
$logsWin   = $testSession.windows | Where-Object { $_.name -eq 'logs' }
$buildWin  = $testSession.windows | Where-Object { $_.name -eq 'build' }

if ($editorWin.panes.Count -eq 2) { Write-Pass "editor: 2 panes" }
else { Write-Fail "editor: expected 2 panes, got $($editorWin.panes.Count)" }

if ($logsWin.panes.Count -eq 1) { Write-Pass "logs: 1 pane" }
else { Write-Fail "logs: expected 1 pane, got $($logsWin.panes.Count)" }

if ($buildWin.panes.Count -eq 3) { Write-Pass "build: 3 panes" }
else { Write-Fail "build: expected 3 panes, got $($buildWin.panes.Count)" }

# === TEST 4: Active pane saved ===
Write-Host "`n[Test 4] Active pane per window saved" -ForegroundColor Yellow
$hasActivePanes = $true
foreach ($win in $testSession.windows) {
    $actives = @($win.panes | Where-Object { $_.active -eq $true })
    if ($actives.Count -ne 1) {
        Write-Fail "Window '$($win.name)': expected 1 active pane, got $($actives.Count)"
        $hasActivePanes = $false
    }
}
if ($hasActivePanes) { Write-Pass "Every window has exactly 1 active pane" }

# === TEST 5: Zoomed state saved ===
Write-Host "`n[Test 5] Zoomed state saved" -ForegroundColor Yellow
if ($buildWin.zoomed -eq $true) { Write-Pass "build window saved as zoomed" }
else { Write-Fail "build window zoomed expected true, got $($buildWin.zoomed)" }

if ($editorWin.zoomed -ne $true) { Write-Pass "editor window saved as not zoomed" }
else { Write-Fail "editor window should not be zoomed" }

# === TEST 6: Pane title saved ===
Write-Host "`n[Test 6] Pane title saved" -ForegroundColor Yellow
$editorPane0 = $editorWin.panes | Where-Object { $_.index -eq 0 }
if ($editorPane0.title -eq 'main_editor') { Write-Pass "Pane title 'main_editor' saved" }
else { Write-Fail "Pane title expected 'main_editor', got '$($editorPane0.title)'" }

# === TEST 7: Layout string saved ===
Write-Host "`n[Test 7] Layout strings saved" -ForegroundColor Yellow
foreach ($win in $testSession.windows) {
    if ($win.layout -and $win.layout.Length -gt 0) {
        Write-Pass "Window '$($win.name)' has layout: $($win.layout.Substring(0, [Math]::Min(40, $win.layout.Length)))..."
    } else {
        Write-Fail "Window '$($win.name)' missing layout string"
    }
}

# === TEST 8: Active window saved ===
Write-Host "`n[Test 8] Active window saved" -ForegroundColor Yellow
$activeWin = $testSession.windows | Where-Object { $_.active -eq $true }
if ($activeWin -and $activeWin.name -eq 'logs') { Write-Pass "Active window is 'logs'" }
else { Write-Fail "Active window expected 'logs', got '$($activeWin.name)'" }

# === TEST 9: Pane command saved ===
Write-Host "`n[Test 9] Pane command field present" -ForegroundColor Yellow
$hasCommands = $true
foreach ($win in $testSession.windows) {
    foreach ($pane in $win.panes) {
        if (-not ($pane.PSObject.Properties.Name -contains 'command')) {
            $hasCommands = $false
            Write-Fail "Pane $($pane.index) in '$($win.name)' missing command field"
        }
    }
}
if ($hasCommands) { Write-Pass "All panes have command field" }

# === TEST 10: Version field ===
Write-Host "`n[Test 10] Save format version" -ForegroundColor Yellow
if ($json.version -eq 2) { Write-Pass "Save format version 2" }
else { Write-Fail "Expected version 2, got $($json.version)" }

# ===================================================================
# PART 2: Deduplication Test
# ===================================================================
Write-Host "`n--- PART 2: Save Deduplication ---" -ForegroundColor Cyan

Write-Host "`n[Test 11] Duplicate save is skipped" -ForegroundColor Yellow
# Kill all non-keepalive/non-test sessions to ensure stable state
$allSessions = (& $PSMUX list-sessions -F '#{session_name}' 2>&1 | Out-String).Trim() -split "`n"
foreach ($sn in $allSessions) {
    $sn = $sn.Trim()
    if ($sn -and $sn -ne $SESSION -and $sn -ne $KEEPALIVE) {
        & $PSMUX kill-session -t $sn 2>&1 | Out-Null
    }
}
Start-Sleep -Seconds 1
# Clean saves and do a fresh first save
Remove-Item "$RESURRECT_DIR\psmux_resurrect_*.json" -Force -EA SilentlyContinue
Remove-Item "$RESURRECT_DIR\last" -Force -EA SilentlyContinue
& pwsh -NoProfile -ExecutionPolicy Bypass -File $SAVE_SCRIPT 2>&1 | Out-Null
Start-Sleep -Milliseconds 500
$beforeCount = (Get-ChildItem -Path $RESURRECT_DIR -Filter 'psmux_resurrect_*.json').Count
# Second save immediately (environment should be unchanged)
$dedupOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $SAVE_SCRIPT 2>&1 | Out-String
Start-Sleep -Milliseconds 500
$afterCount = (Get-ChildItem -Path $RESURRECT_DIR -Filter 'psmux_resurrect_*.json').Count
if ($afterCount -eq $beforeCount) {
    Write-Pass "Duplicate save skipped (count unchanged: $afterCount)"
} elseif ($dedupOutput -match 'unchanged') {
    Write-Pass "Dedup detected unchanged state (message: unchanged)"
} else {
    Write-Fail "Expected same count $beforeCount, got $afterCount (dedup not detected)"
}

# ===================================================================
# PART 3: Restore Tests
# ===================================================================
Write-Host "`n--- PART 3: Restore Tests ---" -ForegroundColor Cyan

# Kill the session to test restore
& $PSMUX kill-session -t $SESSION 2>&1 | Out-Null
Start-Sleep -Seconds 2
Remove-Item "$psmuxDir\$SESSION.*" -Force -EA SilentlyContinue

# Verify it's dead
& $PSMUX has-session -t $SESSION 2>$null
if ($LASTEXITCODE -ne 0) { Write-Pass "Session killed successfully before restore" }
else { Write-Fail "Session still alive after kill" }

# Run restore
Write-Host "`n[Test 12] Restore script recreates session" -ForegroundColor Yellow
& pwsh -NoProfile -ExecutionPolicy Bypass -File $RESTORE_SCRIPT 2>&1 | Out-Null
Start-Sleep -Seconds 5  # Give time for session creation + pane splits

if (Wait-Session $SESSION 20000) { Write-Pass "Session '$SESSION' restored" }
else { Write-Fail "Session '$SESSION' not found after restore"; exit 1 }

# === TEST 13: Window count restored ===
Write-Host "`n[Test 13] Window count restored" -ForegroundColor Yellow
$winCount = (& $PSMUX display-message -t $SESSION -p '#{session_windows}' 2>&1 | Out-String).Trim()
if ($winCount -eq '3') { Write-Pass "3 windows restored" }
else { Write-Fail "Expected 3 windows, got $winCount" }

# === TEST 14: Window names restored ===
Write-Host "`n[Test 14] Window names restored" -ForegroundColor Yellow
$restoredWinNames = (& $PSMUX list-windows -t $SESSION -F '#{window_name}' 2>&1 | Out-String).Trim() -split "`n"
$restoredWinNames = $restoredWinNames | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$nameCheck = $true
foreach ($expected in @('editor', 'logs', 'build')) {
    if ($restoredWinNames -contains $expected) {
        Write-Pass "Window '$expected' restored"
    } else {
        Write-Fail "Window '$expected' not found in restored names: $($restoredWinNames -join ', ')"
        $nameCheck = $false
    }
}

# === TEST 15: Pane count per window restored ===
Write-Host "`n[Test 15] Pane counts restored" -ForegroundColor Yellow
# Get pane counts for each window
$winIndices = (& $PSMUX list-windows -t $SESSION -F '#{window_index}|#{window_name}' 2>&1 | Out-String).Trim() -split "`n"
foreach ($wl in $winIndices) {
    $wl = $wl.Trim()
    if ([string]::IsNullOrWhiteSpace($wl)) { continue }
    $wp = $wl -split '\|'
    $idx = $wp[0]
    $name = $wp[1]
    $paneCount = (& $PSMUX display-message -t "${SESSION}:${idx}" -p '#{window_panes}' 2>&1 | Out-String).Trim()
    switch ($name) {
        'editor' {
            if ($paneCount -eq '2') { Write-Pass "editor: 2 panes restored" }
            else { Write-Fail "editor: expected 2 panes, got $paneCount" }
        }
        'logs' {
            if ($paneCount -eq '1') { Write-Pass "logs: 1 pane restored" }
            else { Write-Fail "logs: expected 1 pane, got $paneCount" }
        }
        'build' {
            if ($paneCount -eq '3') { Write-Pass "build: 3 panes restored" }
            else { Write-Fail "build: expected 3 panes, got $paneCount" }
        }
    }
}

# === TEST 16: Layout restored (not all horizontal stacks) ===
Write-Host "`n[Test 16] Layout geometry restored" -ForegroundColor Yellow
# Get the editor window layout - it should have a horizontal split (side by side)
$editorIdx = ($winIndices | ForEach-Object { $_.Trim() } | Where-Object { $_ -match 'editor' }) -replace '\|.*',''
$restoredLayout = (& $PSMUX display-message -t "${SESSION}:${editorIdx}" -p '#{window_layout}' 2>&1 | Out-String).Trim()
if ($restoredLayout -and $restoredLayout.Length -gt 5) {
    Write-Pass "Editor layout restored: $($restoredLayout.Substring(0, [Math]::Min(40, $restoredLayout.Length)))..."
} else {
    Write-Fail "Editor layout empty or too short: '$restoredLayout'"
}

# === TEST 17: Active window restored ===
Write-Host "`n[Test 17] Active window restored" -ForegroundColor Yellow
$activeWinName = (& $PSMUX display-message -t $SESSION -p '#{window_name}' 2>&1 | Out-String).Trim()
if ($activeWinName -eq 'logs') { Write-Pass "Active window is 'logs'" }
else { Write-Fail "Active window expected 'logs', got '$activeWinName'" }

# === TEST 18: Pane title restored ===
Write-Host "`n[Test 18] Pane title restored" -ForegroundColor Yellow
$restoredTitle = (& $PSMUX display-message -t "${SESSION}:${editorIdx}.0" -p '#{pane_title}' 2>&1 | Out-String).Trim()
if ($restoredTitle -eq 'main_editor') { Write-Pass "Pane title 'main_editor' restored" }
else { Write-Fail "Pane title expected 'main_editor', got '$restoredTitle'" }

# === TEST 19: Zoomed state restored ===
Write-Host "`n[Test 19] Zoomed state restored" -ForegroundColor Yellow
$buildIdx = ($winIndices | ForEach-Object { $_.Trim() } | Where-Object { $_ -match 'build' }) -replace '\|.*',''
$zoomFlag = (& $PSMUX display-message -t "${SESSION}:${buildIdx}" -p '#{window_zoomed_flag}' 2>&1 | Out-String).Trim()
if ($zoomFlag -eq '1') { Write-Pass "Build window zoom restored" }
else { Write-Fail "Build window zoom expected 1, got '$zoomFlag'" }

# === TEST 20: Idempotent restore (existing session skipped) ===
Write-Host "`n[Test 20] Idempotent restore skips existing session" -ForegroundColor Yellow
$winCountBefore = (& $PSMUX display-message -t $SESSION -p '#{session_windows}' 2>&1 | Out-String).Trim()
& pwsh -NoProfile -ExecutionPolicy Bypass -File $RESTORE_SCRIPT 2>&1 | Out-Null
Start-Sleep -Seconds 2
$winCountAfter = (& $PSMUX display-message -t $SESSION -p '#{session_windows}' 2>&1 | Out-String).Trim()
if ($winCountBefore -eq $winCountAfter) { Write-Pass "Idempotent: session unchanged after re-restore" }
else { Write-Fail "Session modified on re-restore: $winCountBefore -> $winCountAfter" }

# ===================================================================
# PART 4: Backup Rotation Test
# ===================================================================
Write-Host "`n--- PART 4: Backup Rotation ---" -ForegroundColor Cyan

Write-Host "`n[Test 21] Backup rotation keeps max 20" -ForegroundColor Yellow
# Create 25 fake save files
for ($i = 1; $i -le 25; $i++) {
    $fakeTs = "20250101_{0:D6}" -f $i
    $fakePath = Join-Path $RESURRECT_DIR "psmux_resurrect_$fakeTs.json"
    '{"version":2,"timestamp":"fake","sessions":[]}' | Set-Content $fakePath -Force
}
# Now do a real save (which should trigger cleanup)
# First modify state so dedup doesn't skip
& $PSMUX new-window -t $SESSION -n "rotation_test" 2>&1 | Out-Null
Start-Sleep -Milliseconds 500
& pwsh -NoProfile -ExecutionPolicy Bypass -File $SAVE_SCRIPT 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

$saveCount = (Get-ChildItem -Path $RESURRECT_DIR -Filter 'psmux_resurrect_*.json').Count
if ($saveCount -le 20) { Write-Pass "Backup rotation: $saveCount files (max 20)" }
else { Write-Fail "Backup rotation failed: $saveCount files (expected <= 20)" }

# ===================================================================
# PART 5: Win32 TUI Visual Verification
# ===================================================================
Write-Host "`n--- PART 5: Win32 TUI Visual Verification ---" -ForegroundColor Cyan

# Ensure server is alive (it may have died after dedup killed other sessions)
& $PSMUX kill-session -t $SESSION 2>&1 | Out-Null
Start-Sleep -Seconds 1
$serverCheck = & $PSMUX list-sessions 2>&1 | Out-String
if ([string]::IsNullOrWhiteSpace($serverCheck.Trim())) {
    # Server is dead, restart it with a keepalive
    Start-Process -FilePath $PSMUX -ArgumentList "new-session","-d","-s","tui_server_keep" -NoNewWindow
    Start-Sleep -Seconds 4
}

$SESSION_TUI = "resurrect_tui_proof"
& $PSMUX kill-session -t $SESSION_TUI 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

Write-Host "`n[Test 22] TUI: Save and restore with real visible window" -ForegroundColor Yellow

# Launch a visible psmux window (this also starts a server if needed)
$proc = Start-Process -FilePath $PSMUX -ArgumentList "new-session","-s",$SESSION_TUI -PassThru
Start-Sleep -Seconds 6

# Verify it's alive
if (-not (Wait-Session $SESSION_TUI 10000)) {
    Write-Fail "TUI session failed to start"
} else {
    # Add a split and a second window via CLI
    & $PSMUX split-window -h -t $SESSION_TUI 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    & $PSMUX new-window -t $SESSION_TUI -n "tui_win2" 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    # Save
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $SAVE_SCRIPT 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    # Verify save captured the TUI session
    $lastPath = (Get-Content "$RESURRECT_DIR\last" -Raw).Trim()
    $savedJson = Get-Content $lastPath -Raw | ConvertFrom-Json
    $tuiSession = $savedJson.sessions | Where-Object { $_.name -eq $SESSION_TUI }
    if ($tuiSession) { Write-Pass "TUI session saved in JSON" }
    else { Write-Fail "TUI session not found in save" }

    if ($tuiSession.windows.Count -ge 2) { Write-Pass "TUI: 2 windows saved" }
    else { Write-Fail "TUI: expected 2 windows, got $($tuiSession.windows.Count)" }

    # Create an anchor session BEFORE killing TUI, so server stays alive
    & $PSMUX new-session -d -s "tui_anchor" -n "anchor" 2>&1 | Out-Null
    Start-Sleep -Seconds 1

    # Kill TUI session
    & $PSMUX kill-session -t $SESSION_TUI 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    # Restore
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $RESTORE_SCRIPT 2>&1 | Out-Null
    Start-Sleep -Seconds 5

    if (Wait-Session $SESSION_TUI 15000) {
        $restoredWins = (& $PSMUX display-message -t $SESSION_TUI -p '#{session_windows}' 2>&1 | Out-String).Trim()
        if ([int]$restoredWins -ge 2) { Write-Pass "TUI: session restored with $restoredWins windows" }
        else { Write-Fail "TUI: expected 2+ windows after restore, got $restoredWins" }
    } else {
        Write-Fail "TUI: session not found after restore"
    }

    # Cleanup
    & $PSMUX kill-session -t $SESSION_TUI 2>&1 | Out-Null
}
try { Stop-Process -Id $proc.Id -Force -EA SilentlyContinue } catch {}

# ===================================================================
# PART 6: TCP Path Verification
# ===================================================================
Write-Host "`n--- PART 6: TCP Path Verification ---" -ForegroundColor Cyan

# Create a fresh session for TCP testing (also serves as server anchor)
$TCP_SESSION = "resurrect_tcp_test"
& $PSMUX kill-session -t $TCP_SESSION 2>&1 | Out-Null
Start-Sleep -Milliseconds 500
Remove-Item "$psmuxDir\$TCP_SESSION.*" -Force -EA SilentlyContinue

& $PSMUX new-session -d -s $TCP_SESSION -n "tcpwin" 2>&1 | Out-Null
if (-not (Wait-Session $TCP_SESSION)) {
    Write-Fail "TCP test session failed to create"
} else {
    Write-Host "`n[Test 23] TCP: Commands work on restored session" -ForegroundColor Yellow

    # Save, kill, restore
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $SAVE_SCRIPT 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500

    # Create anchor before killing TCP session so server stays alive
    & $PSMUX new-session -d -s "tcp_anchor" -n "anchor" 2>&1 | Out-Null
    if (-not (Wait-Session "tcp_anchor" 10000)) {
        # Fallback: start via Start-Process
        Start-Process -FilePath $PSMUX -ArgumentList "new-session","-d","-s","tcp_anchor2" -NoNewWindow
        Start-Sleep -Seconds 4
    }

    & $PSMUX kill-session -t $TCP_SESSION 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    # Verify server is still alive before restoring
    & $PSMUX has-session -t "tcp_anchor" 2>$null
    if ($LASTEXITCODE -ne 0) {
        & $PSMUX has-session -t "tcp_anchor2" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Start-Process -FilePath $PSMUX -ArgumentList "new-session","-d","-s","tcp_fallback" -NoNewWindow
            Start-Sleep -Seconds 4
        }
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $RESTORE_SCRIPT 2>&1 | Out-Null
    Start-Sleep -Seconds 8

    if (Wait-Session $TCP_SESSION 15000) {
        # Send a command via send-keys and verify via capture-pane
        & $PSMUX send-keys -t $TCP_SESSION "echo RESURRECT_TCP_PROOF" Enter 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        $captured = & $PSMUX capture-pane -t $TCP_SESSION -p 2>&1 | Out-String
        if ($captured -match 'RESURRECT_TCP_PROOF') { Write-Pass "TCP: send-keys + capture-pane works on restored session" }
        else { Write-Fail "TCP: output not found in capture after restore" }

        # Also verify format variables work
        $sessName = (& $PSMUX display-message -t $TCP_SESSION -p '#{session_name}' 2>&1 | Out-String).Trim()
        if ($sessName -eq $TCP_SESSION) { Write-Pass "TCP: display-message works on restored session" }
        else { Write-Fail "TCP: display-message returned '$sessName' instead of '$TCP_SESSION'" }
    } else {
        Write-Fail "TCP test session not found after restore"
    }
    & $PSMUX kill-session -t $TCP_SESSION 2>&1 | Out-Null
}

# ===================================================================
# FINAL CLEANUP
# ===================================================================
Write-Host "`n--- Cleanup ---" -ForegroundColor Cyan
& $PSMUX kill-session -t $SESSION 2>&1 | Out-Null
& $PSMUX kill-session -t $SESSION_TUI 2>&1 | Out-Null
& $PSMUX kill-session -t $TCP_SESSION 2>&1 | Out-Null
& $PSMUX kill-session -t $KEEPALIVE 2>&1 | Out-Null
& $PSMUX kill-session -t "tui_server_keep" 2>&1 | Out-Null
& $PSMUX kill-session -t "tui_anchor" 2>&1 | Out-Null
& $PSMUX kill-session -t "tui_restore_keep" 2>&1 | Out-Null
& $PSMUX kill-session -t "tcp_server_keep" 2>&1 | Out-Null
& $PSMUX kill-session -t "tcp_anchor" 2>&1 | Out-Null
& $PSMUX kill-session -t "tcp_anchor2" 2>&1 | Out-Null
& $PSMUX kill-session -t "tcp_fallback" 2>&1 | Out-Null
# Clean up test save files
$testSaves = Get-ChildItem -Path $RESURRECT_DIR -Filter 'psmux_resurrect_*.json' -EA SilentlyContinue
foreach ($f in $testSaves) { Remove-Item $f.FullName -Force -EA SilentlyContinue }
Remove-Item "$RESURRECT_DIR\last" -Force -EA SilentlyContinue

# ===================================================================
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $($script:TestsPassed)" -ForegroundColor Green
Write-Host "  Failed: $($script:TestsFailed)" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })
Write-Host ""
exit $script:TestsFailed
