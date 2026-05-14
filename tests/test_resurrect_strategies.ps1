#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect: Strategy resolution unit tests
# Validates Get-StrategyCommand in scripts/strategy.ps1 against the
# tmux-resurrect strategy contract: <program>_<strategy>.ps1 lookup, user-dir
# precedence over plugin-dir fallback, fallback-to-original on failure.
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
$PLUGIN_DIR  = Join-Path $PLUGIN_ROOT 'psmux-resurrect'
$STRATEGY_HELPER = Join-Path $PLUGIN_DIR 'scripts\strategy.ps1'

Write-Host "`n=== psmux-resurrect Strategy Tests ===" -ForegroundColor Magenta
Write-Host "Helper: $STRATEGY_HELPER" -ForegroundColor Cyan

Check "strategy.ps1 exists" (Test-Path $STRATEGY_HELPER) $STRATEGY_HELPER
Check "bundled strategies dir exists" (Test-Path (Join-Path $PLUGIN_DIR 'strategies')) ''
Check "nvim_session.ps1 reference strategy exists" `
    (Test-Path (Join-Path $PLUGIN_DIR 'strategies\nvim_session.ps1')) ''

. $STRATEGY_HELPER
Check "Get-StrategyCommand is defined" (Get-Command Get-StrategyCommand -ErrorAction SilentlyContinue) ''

# Scratch dir that stands in for ~/.psmux/strategies during the test.
# We don't change $env:USERPROFILE because psmux derives its socket path from
# it, and switching mid-run would lose the server we're issuing set-option to.
$sandbox = Join-Path $env:TEMP "psmux_resurrect_strategy_test_$([guid]::NewGuid().ToString('N'))"
$sandboxStrategies = Join-Path $sandbox '.psmux\strategies'
$null = New-Item -ItemType Directory -Path $sandboxStrategies -Force

try {
    foreach ($opt in @('@resurrect-strategy-fakeprog','@resurrect-strategy-nostrategy',
                       '@resurrect-strategy-onlyuser','@resurrect-strategy-onlyplugin',
                       '@resurrect-strategy-overridable','@resurrect-strategy-broken',
                       '@resurrect-strategy-nvim','@resurrect-strategy-silent')) {
        & $PSMUX set-option -gu $opt 2>&1 | Out-Null
    }

    # --- Phase 1: no strategy set -> returns original ---
    Write-Host "`n--- Phase 1: No strategy set ---" -ForegroundColor Yellow
    $r = Get-StrategyCommand -OriginalCommand 'nostrategy' -Directory $sandbox `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "no @resurrect-strategy-* -> returns original command" ($r -eq 'nostrategy') "Got: $r"

    # --- Phase 2: strategy set, no file -> returns original ---
    Write-Host "`n--- Phase 2: Strategy set, no file on disk ---" -ForegroundColor Yellow
    & $PSMUX set-option -g '@resurrect-strategy-fakeprog' 'absent' 2>&1 | Out-Null
    $r = Get-StrategyCommand -OriginalCommand 'fakeprog' -Directory $sandbox `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "strategy set but file missing -> returns original" ($r -eq 'fakeprog') "Got: $r"

    # --- Phase 3: user-dir strategy is invoked ---
    Write-Host "`n--- Phase 3: User-dir strategy ---" -ForegroundColor Yellow
    $userStrategyPath = Join-Path $sandboxStrategies 'onlyuser_test.ps1'
    @'
param([string]$OriginalCommand, [string]$Directory)
"USERHIT($OriginalCommand|$Directory)"
'@ | Set-Content -Path $userStrategyPath -Encoding UTF8
    & $PSMUX set-option -g '@resurrect-strategy-onlyuser' 'test' 2>&1 | Out-Null
    $r = Get-StrategyCommand -OriginalCommand 'onlyuser' -Directory 'C:\some\dir' `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "user-dir strategy invoked" ($r -eq 'USERHIT(onlyuser|C:\some\dir)') "Got: $r"

    # --- Phase 4: plugin-dir fallback when user-dir absent ---
    Write-Host "`n--- Phase 4: Plugin-dir fallback ---" -ForegroundColor Yellow
    $tmpProj = Join-Path $sandbox 'with_session'
    $null = New-Item -ItemType Directory -Path $tmpProj -Force
    Set-Content -Path (Join-Path $tmpProj 'Session.vim') -Value '" stub session file' -Encoding ASCII
    & $PSMUX set-option -g '@resurrect-strategy-nvim' 'session' 2>&1 | Out-Null
    $r = Get-StrategyCommand -OriginalCommand 'nvim' -Directory $tmpProj `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "plugin-dir nvim_session strategy invoked when Session.vim present" `
        ($r -eq 'nvim -S') "Got: $r"

    $tmpProj2 = Join-Path $sandbox 'no_session'
    $null = New-Item -ItemType Directory -Path $tmpProj2 -Force
    $r = Get-StrategyCommand -OriginalCommand 'nvim' -Directory $tmpProj2 `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "nvim_session strategy falls back to original when no Session.vim" `
        ($r -eq 'nvim') "Got: $r"

    # --- Phase 5: user-dir overrides plugin-dir ---
    Write-Host "`n--- Phase 5: User-dir overrides plugin-dir ---" -ForegroundColor Yellow
    $userNvimOverride = Join-Path $sandboxStrategies 'nvim_session.ps1'
    @'
param([string]$OriginalCommand, [string]$Directory)
"USER_OVERRIDE_NVIM"
'@ | Set-Content -Path $userNvimOverride -Encoding UTF8
    $r = Get-StrategyCommand -OriginalCommand 'nvim' -Directory $tmpProj `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "user dir takes precedence over plugin dir" ($r -eq 'USER_OVERRIDE_NVIM') "Got: $r"
    Remove-Item $userNvimOverride -Force

    # --- Phase 6: strategy that errors -> fallback to original ---
    Write-Host "`n--- Phase 6: Broken strategy falls back ---" -ForegroundColor Yellow
    $brokenPath = Join-Path $sandboxStrategies 'broken_oops.ps1'
    @'
param([string]$OriginalCommand, [string]$Directory)
throw "intentional failure"
'@ | Set-Content -Path $brokenPath -Encoding UTF8
    & $PSMUX set-option -g '@resurrect-strategy-broken' 'oops' 2>&1 | Out-Null
    $r = Get-StrategyCommand -OriginalCommand 'broken' -Directory $sandbox `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "broken strategy -> fallback to original" ($r -eq 'broken') "Got: $r"

    # --- Phase 7: strategy emitting empty stdout -> fallback to original ---
    Write-Host "`n--- Phase 7: Empty strategy output falls back ---" -ForegroundColor Yellow
    $emptyPath = Join-Path $sandboxStrategies 'silent_quiet.ps1'
    'param([string]$OriginalCommand,[string]$Directory)' | Set-Content -Path $emptyPath -Encoding UTF8
    & $PSMUX set-option -g '@resurrect-strategy-silent' 'quiet' 2>&1 | Out-Null
    $r = Get-StrategyCommand -OriginalCommand 'silent' -Directory $sandbox `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "empty-stdout strategy -> fallback to original" ($r -eq 'silent') "Got: $r"

    # --- Phase 8: command path components stripped before key lookup ---
    Write-Host "`n--- Phase 8: Path/.exe stripping ---" -ForegroundColor Yellow
    # @resurrect-strategy-fakeprog is set ('absent') from Phase 2 but the file does not exist,
    # so we expect the original command to come back. The point is that the key lookup uses
    # 'fakeprog' even when the saved command was a full path with .exe and arguments.
    $r = Get-StrategyCommand -OriginalCommand 'C:\tools\fakeprog.exe --arg' -Directory $sandbox `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "basename stripping picks the right strategy key" `
        ($r -eq 'C:\tools\fakeprog.exe --arg') "Got: $r"

    # Now drop a matching strategy and re-run to prove the key was actually 'fakeprog'
    $fakeprogStrategy = Join-Path $sandboxStrategies 'fakeprog_absent.ps1'
    @'
param([string]$OriginalCommand, [string]$Directory)
"FAKEPROG_HIT($OriginalCommand)"
'@ | Set-Content -Path $fakeprogStrategy -Encoding UTF8
    $r = Get-StrategyCommand -OriginalCommand 'C:\tools\fakeprog.exe --arg' -Directory $sandbox `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "basename strategy receives full original command" `
        ($r -eq 'FAKEPROG_HIT(C:\tools\fakeprog.exe --arg)') "Got: $r"

    # --- Phase 9: empty input handled ---
    Write-Host "`n--- Phase 9: Empty input ---" -ForegroundColor Yellow
    $r = Get-StrategyCommand -OriginalCommand '' -Directory $sandbox `
        -PsmuxBin $PSMUX -PluginDir $PLUGIN_DIR -UserStrategiesDir $sandboxStrategies
    Check "empty original command -> returned as-is" ($r -eq '') "Got: '$r'"
}
finally {
    foreach ($opt in @('@resurrect-strategy-fakeprog','@resurrect-strategy-nostrategy',
                       '@resurrect-strategy-onlyuser','@resurrect-strategy-onlyplugin',
                       '@resurrect-strategy-overridable','@resurrect-strategy-broken',
                       '@resurrect-strategy-nvim','@resurrect-strategy-silent')) {
        & $PSMUX set-option -gu $opt 2>&1 | Out-Null
    }
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n======================================" -ForegroundColor Magenta
Write-Host "  Strategy Tests" -ForegroundColor Magenta
Write-Host "  PASS: $pass  FAIL: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "======================================`n" -ForegroundColor Magenta

if ($fail -gt 0) {
    Write-Host "FAILED TESTS:" -ForegroundColor Red
    $results | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
        Write-Host "  $($_.Test): $($_.Detail)" -ForegroundColor Red
    }
    exit 1
}
Write-Host "All tests passed!" -ForegroundColor Green
exit 0
