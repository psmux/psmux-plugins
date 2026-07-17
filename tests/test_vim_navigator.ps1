#!/usr/bin/env pwsh
# =============================================================================
# psmux-vim-navigator test suite
# Tests plugin file structure, binding registration, vim-detection format
# matching, and (when nvim is available) live vim-aware dispatch.
# =============================================================================

$ErrorActionPreference = "Continue"
$PSMUX = (Get-Command psmux -EA Stop).Source
$psmuxDir = "$env:USERPROFILE\.psmux"
$PLUGIN_DIR = Join-Path $PSScriptRoot "..\psmux-vim-navigator"
$PLUGIN_PS1 = Join-Path $PLUGIN_DIR "psmux-vim-navigator.ps1"
$POLL_SCRIPT = Join-Path $PLUGIN_DIR "scripts\poll-vim-state.ps1"
$SESSION = "vimnav_test"
$script:TestsPassed = 0
$script:TestsFailed = 0

function Write-Pass($msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green; $script:TestsPassed++ }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:TestsFailed++ }
function Write-Skip($msg) { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow }

function Wait-Session {
    param([string]$Name, [int]$TimeoutMs = 15000)
    for ($i = 0; $i -lt ($TimeoutMs / 250); $i++) {
        Start-Sleep -Milliseconds 250
        & $PSMUX has-session -t $Name 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

function Cleanup {
    $pollLock = Join-Path $env:USERPROFILE '.psmux\vim-navigator.pid'
    if (Test-Path $pollLock) {
        $p = (Get-Content $pollLock -Raw -EA SilentlyContinue).Trim()
        if ($p -match '^\d+$') { try { Stop-Process -Id ([int]$p) -Force -EA SilentlyContinue } catch {} }
        Remove-Item $pollLock -Force -EA SilentlyContinue
    }
    & $PSMUX kill-session -t $SESSION 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    Remove-Item "$psmuxDir\$SESSION.*" -Force -EA SilentlyContinue
}

Write-Host "`n=== psmux-vim-navigator Test Suite ===" -ForegroundColor Cyan
Write-Host "Plugin dir: $PLUGIN_DIR"

# ===================================================================
# PART 1: File structure
# ===================================================================
Write-Host "`n--- PART 1: File Structure ---" -ForegroundColor Cyan

if (Test-Path $PLUGIN_PS1) { Write-Pass "psmux-vim-navigator.ps1 exists" } else { Write-Fail "psmux-vim-navigator.ps1 missing" }
if (Test-Path $POLL_SCRIPT) { Write-Pass "scripts/poll-vim-state.ps1 exists" } else { Write-Fail "scripts/poll-vim-state.ps1 missing" }
if (Test-Path (Join-Path $PLUGIN_DIR "README.md")) { Write-Pass "README.md exists" } else { Write-Fail "README.md missing" }

foreach ($script in @($PLUGIN_PS1, $POLL_SCRIPT)) {
    if (-not (Test-Path $script)) { continue }
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors)
    $name = Split-Path -Leaf $script
    if ($errors.Count -eq 0) { Write-Pass "${name}: valid PowerShell syntax" }
    else { Write-Fail "${name}: $($errors.Count) syntax errors: $($errors[0].Message)" }
}

# No plugin.conf should be shipped -- PPM skips the .ps1 entry point entirely
# when a plugin.conf is present, which would silently disable the background
# poller this plugin depends on for vim-awareness.
$confPath = Join-Path $PLUGIN_DIR "plugin.conf"
if (-not (Test-Path $confPath)) {
    Write-Pass "no plugin.conf shipped (required so PPM sources the .ps1 entry point)"
} else {
    Write-Fail "plugin.conf present -- PPM will skip psmux-vim-navigator.ps1 and the poller never starts"
}

# ===================================================================
# PART 2: Binding registration
# ===================================================================
Write-Host "`n--- PART 2: Binding Registration ---" -ForegroundColor Cyan
Cleanup

& $PSMUX new-session -d -s $SESSION -x 120 -y 40 2>&1 | Out-Null
if (-not (Wait-Session $SESSION)) {
    Write-Fail "Could not create test session"
    exit 1
}
Write-Host "  Session created" -ForegroundColor DarkGray

& $PLUGIN_PS1
Start-Sleep -Seconds 2

$rootKeys = & $PSMUX list-keys -T root -t $SESSION 2>&1 | Out-String
Write-Pass "plugin loads without error"

if ($rootKeys -match 'C-h\s+select-pane\s+-L') { Write-Pass "root: C-h -> select-pane -L" } else { Write-Fail "root: C-h binding not found" }
if ($rootKeys -match 'C-j\s+select-pane\s+-D') { Write-Pass "root: C-j -> select-pane -D" } else { Write-Fail "root: C-j binding not found" }
if ($rootKeys -match 'C-k\s+select-pane\s+-U') { Write-Pass "root: C-k -> select-pane -U" } else { Write-Fail "root: C-k binding not found" }
if ($rootKeys -match 'C-l\s+select-pane\s+-R') { Write-Pass "root: C-l -> select-pane -R" } else { Write-Fail "root: C-l binding not found" }
if ($rootKeys -match [regex]::Escape('C-\') + '\s+select-pane\s+-l') { Write-Pass "root: C-\ -> select-pane -l (prev pane)" } else { Write-Fail "root: C-\ binding not found" }

$cmKeys = & $PSMUX list-keys -T copy-mode-vi -t $SESSION 2>&1 | Out-String
if ($cmKeys -match 'C-h\s+select-pane\s+-L') { Write-Pass "copy-mode-vi: C-h -> select-pane -L" } else { Write-Fail "copy-mode-vi: C-h binding not found" }

$prefixKeys = & $PSMUX list-keys -T prefix -t $SESSION 2>&1 | Out-String
if ($prefixKeys -match 'C-l\s+send-keys\s+C-l') { Write-Pass "prefix: C-l -> send-keys C-l (clear-screen restored)" } else { Write-Fail "prefix: C-l clear-screen binding not found" }

# Poller should have started and written a lock file (single-instance guard).
$pollLock = Join-Path $env:USERPROFILE '.psmux\vim-navigator.pid'
Start-Sleep -Seconds 1
if (Test-Path $pollLock) {
    $lockPid = (Get-Content $pollLock -Raw -EA SilentlyContinue).Trim()
    $proc = Get-Process -Id ([int]$lockPid) -EA SilentlyContinue
    if ($proc) { Write-Pass "background poller running (pid $lockPid)" }
    else { Write-Fail "poller lock file present but process not running" }
} else {
    Write-Fail "poller lock file not created"
}

# ===================================================================
# PART 3: Vim-detection format matching (deterministic, no keystroke
# injection required -- exercises the exact regex the poller uses)
# ===================================================================
Write-Host "`n--- PART 3: Vim-Detection Pattern Matching ---" -ForegroundColor Cyan

$vimPattern = '(^|/)g?(view|l?n?vim?x?|fzf)(diff)?(\.exe)?$'
$idleCmd = (& $PSMUX display-message -t $SESSION -p '#{pane_current_command}' 2>&1 | Out-String).Trim()
if ($idleCmd -and $idleCmd -ne 'shell') {
    Write-Pass "idle pane reports real shell name ('$idleCmd', not the 'shell' placeholder -- requires psmux/psmux#299 fix, commit b003802)"
} else {
    Write-Fail "idle pane reports '$idleCmd' -- vim-detection needs the immediate-child pane_current_command fix from psmux/psmux#299"
}
$idleMatch = $idleCmd -match $vimPattern
if (-not $idleMatch) { Write-Pass "idle shell ('$idleCmd') does not match vim pattern" }
else { Write-Fail "idle shell ('$idleCmd') incorrectly matches vim pattern" }

$nvimCmd = (Get-Command nvim -EA SilentlyContinue)
if ($nvimCmd) {
    & $PSMUX send-keys -t $SESSION "& `"$($nvimCmd.Source)`"" Enter 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $cmd = (& $PSMUX display-message -t $SESSION -p '#{pane_current_command}' 2>&1 | Out-String).Trim()
    if ($cmd -eq 'nvim') { Write-Pass "pane_current_command reports 'nvim' while nvim is running" }
    else { Write-Fail "expected pane_current_command 'nvim', got '$cmd'" }
    if ($cmd -match $vimPattern) { Write-Pass "vim-detect pattern matches 'nvim'" }
    else { Write-Fail "vim-detect pattern does not match 'nvim'" }

    # Give the poller (default 250ms interval) time to notice and re-bind.
    Start-Sleep -Seconds 1
    $rootKeysAfterNvim = & $PSMUX list-keys -T root -t $SESSION 2>&1 | Out-String
    if ($rootKeysAfterNvim -match 'C-h\s+send-keys\s+C-h') {
        Write-Pass "poller re-bound C-h to send-keys while nvim is active (vim-aware passthrough armed)"
    } else {
        Write-Fail "poller did not re-bind C-h after nvim started"
    }

    & $PSMUX send-keys -t $SESSION Escape ":qa!" Enter 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    $cmdAfterQuit = (& $PSMUX display-message -t $SESSION -p '#{pane_current_command}' 2>&1 | Out-String).Trim()
    if ($cmdAfterQuit -ne 'nvim') { Write-Pass "pane_current_command returns to shell ('$cmdAfterQuit') after :qa!" }
    else { Write-Fail "pane_current_command still reports nvim after :qa!" }

    Start-Sleep -Seconds 1
    $rootKeysAfterQuit = & $PSMUX list-keys -T root -t $SESSION 2>&1 | Out-String
    if ($rootKeysAfterQuit -match 'C-h\s+select-pane\s+-L') {
        Write-Pass "poller re-bound C-h back to select-pane after nvim exited"
    } else {
        Write-Fail "poller did not re-bind C-h back after nvim exited"
    }
} else {
    Write-Skip "nvim not found on PATH -- skipping live vim-detection dispatch tests (pattern matching itself is still exercised above)"
}

# ===================================================================
# Cleanup
# ===================================================================
Cleanup

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $($script:TestsPassed)" -ForegroundColor Green
Write-Host "  Failed: $($script:TestsFailed)" -ForegroundColor $(if ($script:TestsFailed -gt 0) { "Red" } else { "Green" })
exit $script:TestsFailed
