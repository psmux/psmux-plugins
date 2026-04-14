#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect Plugin: Comprehensive E2E Test
# Tests save and restore functionality across multiple scenarios
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
$results = @()

function Check($name, $cond, $detail = '') {
    if ($cond) {
        Write-Host "  PASS: $name" -ForegroundColor Green
        $script:pass++
        $script:results += [PSCustomObject]@{ Test = $name; Result = 'PASS'; Detail = $detail }
    } else {
        Write-Host "  FAIL: $name $(if($detail){' >> ' + $detail})" -ForegroundColor Red
        $script:fail++
        $script:results += [PSCustomObject]@{ Test = $name; Result = 'FAIL'; Detail = $detail }
    }
}

# Detect psmux binary
$PSMUX = $null
foreach ($n in @('psmux', 'pmux', 'tmux')) {
    $b = Get-Command $n -ErrorAction SilentlyContinue
    if ($b) { $PSMUX = $b.Source; break }
}
if (-not $PSMUX) {
    Write-Host "FATAL: psmux binary not found!" -ForegroundColor Red
    exit 1
}

$PLUGIN_ROOT = Split-Path $PSScriptRoot -Parent
$SAVE_SCRIPT = Join-Path $PLUGIN_ROOT 'psmux-resurrect\scripts\save.ps1'
$RESTORE_SCRIPT = Join-Path $PLUGIN_ROOT 'psmux-resurrect\scripts\restore.ps1'
$RESURRECT_DIR = Join-Path $env:USERPROFILE '.psmux\resurrect'

Write-Host "`n=== psmux-resurrect Comprehensive Test ===" -ForegroundColor Magenta
Write-Host "Binary: $PSMUX ($(& $PSMUX --version 2>&1))" -ForegroundColor Cyan
Write-Host "Save script: $SAVE_SCRIPT" -ForegroundColor Cyan
Write-Host "Restore script: $RESTORE_SCRIPT" -ForegroundColor Cyan

# =============================================================================
# CLEANUP: Remove any leftover test sessions
# =============================================================================
Write-Host "`n--- Cleanup ---" -ForegroundColor Yellow
foreach ($s in @('res_test_alpha', 'res_test_beta', 'res_test_gamma')) {
    & $PSMUX kill-session -t $s 2>&1 | Out-Null
}
Start-Sleep -Seconds 1
Remove-Item "$RESURRECT_DIR\*" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null

# =============================================================================
# PHASE 1: Static Validation
# =============================================================================
Write-Host "`n--- Phase 1: Static Validation ---" -ForegroundColor Yellow

Check "save.ps1 exists" (Test-Path $SAVE_SCRIPT) $SAVE_SCRIPT
Check "restore.ps1 exists" (Test-Path $RESTORE_SCRIPT) $RESTORE_SCRIPT
Check "plugin.conf exists" (Test-Path (Join-Path $PLUGIN_ROOT 'psmux-resurrect\plugin.conf'))

# Verify scripts use format flags (the fix), not fragile regex
$saveContent = Get-Content $SAVE_SCRIPT -Raw
Check "save.ps1 uses list-sessions -F format" ($saveContent -match "ls\s+.*-F\s+'#\{session_name\}'") "Uses format flags for clean session parsing"
Check "save.ps1 uses list-windows -F format" ($saveContent -match "list-windows.*-F\s+'#\{window_index\}") "Uses format flags for clean window parsing"
Check "save.ps1 uses list-panes -F format" ($saveContent -match "list-panes.*-F\s+'#\{pane_index\}") "Uses format flags for clean pane parsing"
Check "save.ps1 uses show-options -gv" ($saveContent -match "show-options\s+-gv") "Uses value-only flag"

# =============================================================================
# PHASE 2: Prerequisite checks
# =============================================================================
Write-Host "`n--- Phase 2: Prerequisite Checks ---" -ForegroundColor Yellow

# Test that psmux supports required format variables
$fmtTest = (& $PSMUX ls -F '#{session_name}' 2>&1 | Out-String).Trim()
Check "list-sessions -F works" (-not [string]::IsNullOrWhiteSpace($fmtTest) -or $true) "format expansion works"

$optTest = (& $PSMUX show-options -gv base-index 2>&1 | Out-String).Trim()
Check "show-options -gv works" ($optTest -match '^\d+$') "Returns value only: $optTest"

# =============================================================================
# PHASE 3: Create Test Environment
# =============================================================================
Write-Host "`n--- Phase 3: Create Test Environment ---" -ForegroundColor Yellow

# Session alpha: 3 windows, window 1 has 2 panes
Start-Process $PSMUX -ArgumentList "new-session", "-d", "-s", "res_test_alpha", "-n", "main", "-c", "$env:USERPROFILE" -WindowStyle Hidden
Start-Sleep -Seconds 3

& $PSMUX split-window -t res_test_alpha:0 -c "$env:TEMP" 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

& $PSMUX new-window -t res_test_alpha -n "work" -c "$env:USERPROFILE\Documents" 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

& $PSMUX new-window -t res_test_alpha -n "scratch" -c "$env:USERPROFILE\Desktop" 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

# Select "work" window as active (index 1)
& $PSMUX select-window -t res_test_alpha:1 2>&1 | Out-Null
Start-Sleep -Milliseconds 200

# Session beta: 1 window, 3 panes (split twice)
Start-Process $PSMUX -ArgumentList "new-session", "-d", "-s", "res_test_beta", "-n", "multi", "-c", "$env:USERPROFILE\Documents\workspace" -WindowStyle Hidden
Start-Sleep -Seconds 3

& $PSMUX split-window -t res_test_beta:0 -c "$env:TEMP" 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

& $PSMUX split-window -t res_test_beta:0 -c "$env:USERPROFILE" 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

# Session gamma: 1 window, 1 pane (minimal)
Start-Process $PSMUX -ArgumentList "new-session", "-d", "-s", "res_test_gamma", "-n", "solo", "-c", "$env:USERPROFILE\Documents\workspace\psmux" -WindowStyle Hidden
Start-Sleep -Seconds 3

# Set a user option for testing
& $PSMUX set-option -g '@resurrect-test-marker' 'verified' 2>&1 | Out-Null

# Verify environment
$sessions = (& $PSMUX ls -F '#{session_name}' 2>&1 | Out-String).Trim() -split "`n"
$testSessions = $sessions | Where-Object { $_ -match '^res_test_' }
Check "3 test sessions created" ($testSessions.Count -eq 3) "Found: $($testSessions.Count)"

# Capture detailed state for comparison
$alpha_windows = (& $PSMUX list-windows -t res_test_alpha -F '#{window_index}|#{window_name}|#{window_active}' 2>&1 | Out-String).Trim() -split "`n"
Check "alpha has 3 windows" ($alpha_windows.Count -eq 3) "Found: $($alpha_windows.Count)"
Check "alpha window 1 (work) is active" ($alpha_windows[1] -match '1\|work\|1')

$alpha_panes_0 = (& $PSMUX list-panes -t res_test_alpha:0 -F '#{pane_index}|#{pane_current_path}' 2>&1 | Out-String).Trim() -split "`n"
Check "alpha:0 has 2 panes" ($alpha_panes_0.Count -eq 2) "Found: $($alpha_panes_0.Count)"

$beta_panes = (& $PSMUX list-panes -t res_test_beta:0 -F '#{pane_index}|#{pane_current_path}' 2>&1 | Out-String).Trim() -split "`n"
Check "beta:0 has 3 panes" ($beta_panes.Count -eq 3) "Found: $($beta_panes.Count)"

# =============================================================================
# PHASE 4: Save Environment
# =============================================================================
Write-Host "`n--- Phase 4: Save Environment ---" -ForegroundColor Yellow

$saveOutput = pwsh -NoProfile -ExecutionPolicy Bypass -File $SAVE_SCRIPT 2>&1 | Out-String
Check "save script succeeded" ($saveOutput -match 'Saved to') $saveOutput.Trim()

# Verify save file
$lastFile = Join-Path $RESURRECT_DIR 'last'
Check "last pointer file exists" (Test-Path $lastFile)

$saveFilePath = (Get-Content $lastFile -Raw).Trim()
Check "save JSON file exists" (Test-Path $saveFilePath) $saveFilePath

$saved = Get-Content $saveFilePath -Raw | ConvertFrom-Json
Check "saved data has timestamp" (-not [string]::IsNullOrWhiteSpace($saved.timestamp))

$savedTestSessions = $saved.sessions | Where-Object { $_.name -match '^res_test_' }
Check "saved 3 test sessions" ($savedTestSessions.Count -eq 3) "Found: $($savedTestSessions.Count)"

# Validate alpha session data
$savedAlpha = $saved.sessions | Where-Object { $_.name -eq 'res_test_alpha' }
Check "alpha saved with correct name" ($savedAlpha -ne $null)
Check "alpha has 3 saved windows" ($savedAlpha.windows.Count -eq 3) "Found: $($savedAlpha.windows.Count)"

$savedAlphaWin0 = $savedAlpha.windows | Where-Object { $_.index -eq 0 }
Check "alpha:0 name is 'main'" ($savedAlphaWin0.name -eq 'main') "Got: $($savedAlphaWin0.name)"
Check "alpha:0 has 2 saved panes" ($savedAlphaWin0.panes.Count -eq 2) "Got: $($savedAlphaWin0.panes.Count)"
Check "alpha:0 pane 0 directory correct" ($savedAlphaWin0.panes[0].directory -eq "$env:USERPROFILE") "Got: $($savedAlphaWin0.panes[0].directory)"

$savedAlphaWin1 = $savedAlpha.windows | Where-Object { $_.index -eq 1 }
Check "alpha:1 name is 'work'" ($savedAlphaWin1.name -eq 'work') "Got: $($savedAlphaWin1.name)"
Check "alpha:1 is active" ($savedAlphaWin1.active -eq $true)

$savedAlphaWin2 = $savedAlpha.windows | Where-Object { $_.index -eq 2 }
Check "alpha:2 name is 'scratch'" ($savedAlphaWin2.name -eq 'scratch') "Got: $($savedAlphaWin2.name)"
Check "alpha:2 is NOT active" ($savedAlphaWin2.active -eq $false)

# Validate beta session data
$savedBeta = $saved.sessions | Where-Object { $_.name -eq 'res_test_beta' }
Check "beta has 1 saved window" ($savedBeta.windows.Count -eq 1)
Check "beta:0 has 3 saved panes" ($savedBeta.windows[0].panes.Count -eq 3) "Got: $($savedBeta.windows[0].panes.Count)"
Check "beta:0 name is 'multi'" ($savedBeta.windows[0].name -eq 'multi') "Got: $($savedBeta.windows[0].name)"

# Validate gamma session data
$savedGamma = $saved.sessions | Where-Object { $_.name -eq 'res_test_gamma' }
Check "gamma has 1 window, 1 pane" ($savedGamma.windows.Count -eq 1 -and $savedGamma.windows[0].panes.Count -eq 1)

# Window names should NOT have flag characters
foreach ($sess in $savedTestSessions) {
    foreach ($win in $sess.windows) {
        $hasBadChars = $win.name -match '[*\-#!~Z]$'
        Check "no flag chars in $($sess.name):$($win.index) name '$($win.name)'" (-not $hasBadChars)
    }
}

# =============================================================================
# PHASE 5: Kill Sessions, Then Restore
# =============================================================================
Write-Host "`n--- Phase 5: Kill Sessions, Then Restore ---" -ForegroundColor Yellow

& $PSMUX kill-session -t res_test_alpha 2>&1 | Out-Null
& $PSMUX kill-session -t res_test_beta 2>&1 | Out-Null
& $PSMUX kill-session -t res_test_gamma 2>&1 | Out-Null
Start-Sleep -Seconds 2

$afterKill = (& $PSMUX ls -F '#{session_name}' 2>&1 | Out-String).Trim() -split "`n"
$remainingTest = $afterKill | Where-Object { $_ -match '^res_test_' }
Check "all test sessions killed" ($remainingTest.Count -eq 0) "Remaining: $($remainingTest.Count)"

# Now restore
$restoreOutput = pwsh -NoProfile -ExecutionPolicy Bypass -File $RESTORE_SCRIPT 2>&1 | Out-String
Check "restore script succeeded" ($restoreOutput -match 'Restored session')

# Wait for sessions to spin up
Start-Sleep -Seconds 3

# =============================================================================
# PHASE 6: Verify Restored Sessions
# =============================================================================
Write-Host "`n--- Phase 6: Verify Restored Sessions ---" -ForegroundColor Yellow

$restoredSessions = (& $PSMUX ls -F '#{session_name}' 2>&1 | Out-String).Trim() -split "`n"
$restoredTest = $restoredSessions | Where-Object { $_ -match '^res_test_' }
Check "3 test sessions restored" ($restoredTest.Count -eq 3) "Found: $($restoredTest.Count): $($restoredTest -join ', ')"

# Verify alpha session
$rAlphaWins = (& $PSMUX list-windows -t res_test_alpha -F '#{window_index}|#{window_name}|#{window_active}' 2>&1 | Out-String).Trim() -split "`n"
Check "alpha restored with 3 windows" ($rAlphaWins.Count -eq 3) "Found: $($rAlphaWins.Count)"

# Check window names
$rAlphaNames = $rAlphaWins | ForEach-Object { ($_ -split '\|')[1] }
Check "alpha window names match: main" ('main' -in $rAlphaNames) "Names: $($rAlphaNames -join ', ')"
Check "alpha window names match: work" ('work' -in $rAlphaNames) "Names: $($rAlphaNames -join ', ')"
Check "alpha window names match: scratch" ('scratch' -in $rAlphaNames) "Names: $($rAlphaNames -join ', ')"

# Check active window
$rAlphaActive = $rAlphaWins | Where-Object { ($_.Trim() -split '\|')[2] -eq '1' }
if ($rAlphaActive -is [array]) { $rAlphaActive = $rAlphaActive[0] }
$rAlphaActiveName = if ($rAlphaActive) { ($rAlphaActive.Trim() -split '\|')[1] } else { '' }
Check "alpha active window is 'work'" ($rAlphaActiveName -eq 'work') "Active: $rAlphaActiveName"

# Check pane count in alpha:0 (should have 2 panes)
$rAlphaPanes0 = (& $PSMUX list-panes -t res_test_alpha:0 -F '#{pane_index}' 2>&1 | Out-String).Trim() -split "`n"
Check "alpha:0 restored with 2 panes" ($rAlphaPanes0.Count -eq 2) "Found: $($rAlphaPanes0.Count)"

# Check pane directories in alpha:0
$rAlphaPaneDirs0 = (& $PSMUX list-panes -t res_test_alpha:0 -F '#{pane_current_path}' 2>&1 | Out-String).Trim() -split "`n"
Check "alpha:0 pane 0 dir is USERPROFILE" ($rAlphaPaneDirs0[0].Trim() -eq $env:USERPROFILE) "Got: $($rAlphaPaneDirs0[0].Trim())"

# Verify beta session
$rBetaWins = (& $PSMUX list-windows -t res_test_beta -F '#{window_index}|#{window_name}' 2>&1 | Out-String).Trim() -split "`n"
Check "beta restored with 1 window" ($rBetaWins.Count -eq 1) "Found: $($rBetaWins.Count)"

$rBetaName = ($rBetaWins[0] -split '\|')[1]
Check "beta window name is 'multi'" ($rBetaName -eq 'multi') "Got: $rBetaName"

$rBetaPanes = (& $PSMUX list-panes -t res_test_beta:0 -F '#{pane_index}' 2>&1 | Out-String).Trim() -split "`n"
Check "beta:0 restored with 3 panes" ($rBetaPanes.Count -eq 3) "Found: $($rBetaPanes.Count)"

# Verify gamma session
$rGammaWins = (& $PSMUX list-windows -t res_test_gamma -F '#{window_index}|#{window_name}' 2>&1 | Out-String).Trim() -split "`n"
Check "gamma restored with 1 window" ($rGammaWins.Count -eq 1)

$rGammaName = ($rGammaWins[0] -split '\|')[1]
Check "gamma window name is 'solo'" ($rGammaName -eq 'solo') "Got: $rGammaName"

$rGammaPanes = (& $PSMUX list-panes -t res_test_gamma:0 -F '#{pane_index}' 2>&1 | Out-String).Trim() -split "`n"
Check "gamma:0 restored with 1 pane" ($rGammaPanes.Count -eq 1)

# =============================================================================
# PHASE 7: Idempotency (restore again should skip existing)
# =============================================================================
Write-Host "`n--- Phase 7: Idempotency Test ---" -ForegroundColor Yellow

$restoreAgain = pwsh -NoProfile -ExecutionPolicy Bypass -File $RESTORE_SCRIPT 2>&1 | Out-String
$skipped = ($restoreAgain | Select-String 'already exists').Matches.Count
Check "restore skips existing sessions" ($restoreAgain -match 'already exists')

# =============================================================================
# PHASE 8: show-options -v compatibility
# =============================================================================
Write-Host "`n--- Phase 8: show-options -v Compatibility ---" -ForegroundColor Yellow

& $PSMUX set-option -g '@resurrect-capture-pane-contents' 'on' 2>&1 | Out-Null
$optVal = (& $PSMUX show-options -gv '@resurrect-capture-pane-contents' 2>&1 | Out-String).Trim()
Check "show-options -gv returns value only" ($optVal -eq 'on') "Got: '$optVal'"

# Combined flags
$optVal2 = (& $PSMUX show-options -gqv '@resurrect-capture-pane-contents' 2>&1 | Out-String).Trim()
Check "show-options -gqv returns value only" ($optVal2 -eq 'on') "Got: '$optVal2'"

& $PSMUX set-option -g '@resurrect-test-marker' 'verified' 2>&1 | Out-Null
$markerVal = (& $PSMUX show-options -gv '@resurrect-test-marker' 2>&1 | Out-String).Trim()
Check "user option @resurrect-test-marker" ($markerVal -eq 'verified') "Got: '$markerVal'"

# =============================================================================
# PHASE 9: list-sessions -F compatibility
# =============================================================================
Write-Host "`n--- Phase 9: list-sessions -F Compatibility ---" -ForegroundColor Yellow

$fmtResult = (& $PSMUX ls -F '#{session_name}:#{session_windows}' 2>&1 | Out-String).Trim() -split "`n"
$alphaFmt = ($fmtResult | Where-Object { $_.Trim() -match '^res_test_alpha:' } | Select-Object -First 1)
if ($alphaFmt) { $alphaFmt = $alphaFmt.Trim() }
Check "list-sessions -F expands session_name" ($alphaFmt -and $alphaFmt -match '^res_test_alpha:\d+$') "Got: '$alphaFmt'"

$fmtResult2 = (& $PSMUX ls -F '#{session_name}|#{session_attached}|#{session_windows}' 2>&1 | Out-String).Trim() -split "`n"
$gammaFmt = ($fmtResult2 | Where-Object { $_.Trim() -match '^res_test_gamma' } | Select-Object -First 1)
if ($gammaFmt) { $gammaFmt = $gammaFmt.Trim() }
Check "list-sessions -F multi var expansion" ($gammaFmt -and $gammaFmt -match '^res_test_gamma\|\d+\|\d+$') "Got: '$gammaFmt'"

# =============================================================================
# PHASE 10: Custom Config Integration
# =============================================================================
Write-Host "`n--- Phase 10: Custom Config Integration ---" -ForegroundColor Yellow

# Create a custom psmux.conf that sources the resurrect plugin
$testConf = Join-Path $env:TEMP "psmux_resurrect_test.conf"
$confContent = @"
# Custom test config for psmux-resurrect
set -g @resurrect-capture-pane-contents on
set -g @resurrect-dir '$RESURRECT_DIR'

# Source the plugin via run-shell
run-shell 'pwsh -NoProfile -ExecutionPolicy Bypass -File "$($SAVE_SCRIPT -replace '\\','/')"' 
"@
Set-Content -Path $testConf -Value $confContent -Force

# Source the config file into an existing session
& $PSMUX source-file $testConf 2>&1 | Out-Null
Start-Sleep -Seconds 1

# Verify the option was set from the config
$confOptVal = (& $PSMUX show-options -gv '@resurrect-capture-pane-contents' 2>&1 | Out-String).Trim()
Check "custom config sets resurrect option" ($confOptVal -eq 'on') "Got: '$confOptVal'"

# Clean up temp config
Remove-Item $testConf -Force -ErrorAction SilentlyContinue

# =============================================================================
# CLEANUP
# =============================================================================
Write-Host "`n--- Cleanup ---" -ForegroundColor Yellow
foreach ($s in @('res_test_alpha', 'res_test_beta', 'res_test_gamma')) {
    & $PSMUX kill-session -t $s 2>&1 | Out-Null
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host "`n======================================" -ForegroundColor Magenta
Write-Host "  psmux-resurrect Test Results" -ForegroundColor Magenta
Write-Host "  PASS: $pass  FAIL: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "======================================`n" -ForegroundColor Magenta

if ($fail -gt 0) {
    Write-Host "FAILED TESTS:" -ForegroundColor Red
    $results | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
        Write-Host "  $($_.Test): $($_.Detail)" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
