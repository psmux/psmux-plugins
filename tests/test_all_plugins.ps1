#!/usr/bin/env pwsh
# =============================================================================
# Comprehensive Plugin Compatibility Test for psmux
# Tests all plugins and themes work correctly with psmux
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0; $warn = 0
$results = @()

function Check($name, $cond, $detail = '') {
    if ($cond) {
        Write-Host "  PASS: $name" -ForegroundColor Green
        $script:pass++
        $script:results += [PSCustomObject]@{ Test = $name; Result = 'PASS'; Detail = $detail }
    } else {
        Write-Host "  FAIL: $name $(if($detail){" - $detail"})" -ForegroundColor Red
        $script:fail++
        $script:results += [PSCustomObject]@{ Test = $name; Result = 'FAIL'; Detail = $detail }
    }
}

function Warn($name, $detail = '') {
    Write-Host "  WARN: $name $(if($detail){" - $detail"})" -ForegroundColor Yellow
    $script:warn++
    $script:results += [PSCustomObject]@{ Test = $name; Result = 'WARN'; Detail = $detail }
}

# --- Detect psmux binary ---
$PSMUX = $null
foreach ($n in @('psmux', 'pmux')) {
    $b = Get-Command $n -ErrorAction SilentlyContinue
    if ($b) { $PSMUX = $b.Source; break }
}
if (-not $PSMUX) {
    Write-Host "FATAL: psmux/pmux binary not found!" -ForegroundColor Red
    exit 1
}
Write-Host "`n=== psmux Plugin Compatibility Test ===" -ForegroundColor Magenta
Write-Host "Binary: $PSMUX" -ForegroundColor Cyan
Write-Host "Version: $(& $PSMUX --version 2>&1)" -ForegroundColor Cyan

$PLUGIN_DIR = "$env:USERPROFILE\.psmux\plugins"
$SESSION = "plugin_test_$(Get-Random -Minimum 1000 -Maximum 9999)"

# =============================================================================
# PHASE 1: Static analysis of plugin.conf files
# =============================================================================
Write-Host "`n--- Phase 1: Static Analysis of plugin.conf files ---" -ForegroundColor Yellow

$plugins = @(
    'psmux-sensible', 'psmux-pain-control',
    'psmux-resurrect', 'psmux-continuum', 'psmux-prefix-highlight',
    'psmux-battery', 'psmux-cpu', 'psmux-logging', 'psmux-sidebar'
)
$themes = @(
    'psmux-theme-dracula', 'psmux-theme-catppuccin', 'psmux-theme-nord',
    'psmux-theme-tokyonight', 'psmux-theme-gruvbox'
)

foreach ($plugin in ($plugins + $themes)) {
    $confPath = Join-Path $PLUGIN_DIR "$plugin\plugin.conf"
    Check "$plugin/plugin.conf exists" (Test-Path $confPath)
    
    if (Test-Path $confPath) {
        $content = Get-Content $confPath -Raw -ErrorAction SilentlyContinue
        
        # Check for bash-isms that shouldn't be in psmux conf
        $hasBashisms = $content -match '#!/bin/bash|#!/usr/bin/env bash|\$\(|`[^"'']'
        Check "${plugin}: no bash-isms" (-not $hasBashisms) $(if($hasBashisms){"Found bash syntax"})
        
        # Check for unix-only paths
        $hasUnixPaths = $content -match '/tmp/|/dev/null|/usr/|/bin/'
        Check "${plugin}: no unix-only paths" (-not $hasUnixPaths) $(if($hasUnixPaths){"Found unix paths"})
        
        # Check that run-shell commands use pwsh (not bash/sh)
        if ($content -match 'run-shell') {
            $runShellLines = ($content -split "`n") | Where-Object { $_ -match 'run-shell' -and $_ -notmatch '^\s*#' }
            foreach ($line in $runShellLines) {
                $usesPwsh = $line -match 'pwsh|powershell'
                Check "${plugin}: run-shell uses pwsh" $usesPwsh "Line: $($line.Trim())"
            }
        }
        
        # Check that bind-key commands have valid key names
        $bindLines = ($content -split "`n") | Where-Object { $_ -match '^\s*bind-key' -and $_ -notmatch '^\s*#' }
        foreach ($line in $bindLines) {
            # Basic syntax check: bind-key [flags] <key> <command>
            $parts = ($line.Trim() -split '\s+')
            $keyIdx = 1
            while ($keyIdx -lt $parts.Count -and $parts[$keyIdx] -match '^-') {
                if ($parts[$keyIdx] -match 'T') { $keyIdx++ }  # -T has an argument
                $keyIdx++
            }
            if ($keyIdx -lt $parts.Count) {
                $keyName = $parts[$keyIdx]
                # Valid keys: letters, C-x, M-x, S-x, special names, quoted chars
                $validKey = $keyName -match "^[a-zA-Z0-9]$|^[CM]-|^S-|^F\d+$|^(Tab|BTab|Space|Enter|Escape|Left|Right|Up|Down)$|^'.'$|^[|\\\-_<>]$"
                if (-not $validKey) {
                    Warn "${plugin}: unusual key name '$keyName'" "May be valid, needs runtime check"
                }
            }
        }
        
        # Verify conf file has no syntax errors (all lines are valid commands or comments)
        $lines = ($content -split "`n") | Where-Object { $_.Trim() -ne '' -and $_.Trim() -notmatch '^\s*#' }
        foreach ($line in $lines) {
            $l = $line.Trim()
            $validCommand = $l -match '^(set|set-option|setw|set-window-option|bind-key|bind|unbind-key|unbind|source-file|source|run-shell|run|if-shell|if|set-hook|set-environment|setenv)\s'
            if (-not $validCommand) {
                Warn "${plugin}: unknown command in conf" "Line: $l"
            }
        }
    }
}

# Check .ps1 entry points exist
Write-Host "`n--- Phase 1b: Check .ps1 entry points ---" -ForegroundColor Yellow
foreach ($plugin in ($plugins + $themes)) {
    $ps1Path = Join-Path $PLUGIN_DIR "$plugin\$plugin.ps1"
    Check "$plugin.ps1 exists" (Test-Path $ps1Path)
}

# Check scripts/ directories for plugins that reference them
Write-Host "`n--- Phase 1c: Check referenced scripts ---" -ForegroundColor Yellow
$scriptChecks = @{
    'psmux-resurrect' = @('scripts/save.ps1', 'scripts/restore.ps1')
    'psmux-continuum' = @('scripts/auto_save.ps1', 'scripts/auto_restore.ps1', 'scripts/boot.ps1')
    'psmux-battery' = @('scripts/battery_status.ps1', 'scripts/battery_info.ps1')
    'psmux-cpu' = @('scripts/system_stats.ps1', 'scripts/cpu_info.ps1')
    'psmux-logging' = @('scripts/toggle_logging.ps1', 'scripts/capture_screen.ps1', 'scripts/capture_history.ps1')
    'psmux-sidebar' = @('scripts/toggle_sidebar.ps1')
}

foreach ($plugin in $scriptChecks.Keys) {
    foreach ($script in $scriptChecks[$plugin]) {
        $scriptPath = Join-Path $PLUGIN_DIR "$plugin\$script"
        Check "$plugin/$script exists" (Test-Path $scriptPath)
    }
}

# PPM scripts
foreach ($script in @('scripts/install_plugins.ps1', 'scripts/update_plugins.ps1', 'scripts/clean_plugins.ps1')) {
    $scriptPath = Join-Path $PLUGIN_DIR "ppm\$script"
    Check "ppm/$script exists" (Test-Path $scriptPath)
}

# =============================================================================
# PHASE 2: Create test configs and validate parsing
# =============================================================================
Write-Host "`n--- Phase 2: Config Parsing Tests ---" -ForegroundColor Yellow

# Test each plugin.conf individually by creating temp configs
foreach ($plugin in ($plugins + $themes)) {
    $confPath = Join-Path $PLUGIN_DIR "$plugin\plugin.conf"
    if (-not (Test-Path $confPath)) { continue }
    
    $testConf = [System.IO.Path]::GetTempFileName() + ".conf"
    # Create a minimal config that sources just this one plugin
    @"
# Test config for $plugin
source-file $($confPath -replace '\\','/')
"@ | Set-Content $testConf -Force
    
    # Start a detached psmux session with this config
    $testSession = "test_${plugin}_$(Get-Random -Min 100 -Max 999)"
    
    # We can't easily test source-file through CLI without a running server.
    # Instead, we'll test all plugins together and query the results.
    Remove-Item $testConf -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# PHASE 3: Runtime Test - Start psmux with all plugins and check state
# =============================================================================
Write-Host "`n--- Phase 3: Runtime Tests (starting psmux session) ---" -ForegroundColor Yellow

# Create a comprehensive test config
$testConfig = "$env:TEMP\psmux_plugin_test.conf"
@"
# Test configuration - all plugins loaded
set -g escape-time 50

# Sensible
source-file ~/.psmux/plugins/psmux-sensible/plugin.conf

# Pain Control
source-file ~/.psmux/plugins/psmux-pain-control/plugin.conf

# Prefix Highlight
source-file ~/.psmux/plugins/psmux-prefix-highlight/plugin.conf

# Battery
source-file ~/.psmux/plugins/psmux-battery/plugin.conf

# CPU
source-file ~/.psmux/plugins/psmux-cpu/plugin.conf

# Logging
source-file ~/.psmux/plugins/psmux-logging/plugin.conf

# Sidebar
source-file ~/.psmux/plugins/psmux-sidebar/plugin.conf

# Resurrect
source-file ~/.psmux/plugins/psmux-resurrect/plugin.conf

# Continuum
source-file ~/.psmux/plugins/psmux-continuum/plugin.conf

# Theme (last)
source-file ~/.psmux/plugins/psmux-theme-gruvbox/plugin.conf
"@ | Set-Content $testConfig -Force

Write-Host "  Starting psmux session '$SESSION' with test config..." -ForegroundColor Cyan

# Temporarily replace .psmux.conf
$origConfig = "$env:USERPROFILE\.psmux.conf"
$backupConfig = "$env:USERPROFILE\.psmux.conf.testbak"
$hadConfig = Test-Path $origConfig
if ($hadConfig) {
    Copy-Item $origConfig $backupConfig -Force
}
Copy-Item $testConfig $origConfig -Force

# Start detached session
$proc = Start-Process -FilePath $PSMUX -ArgumentList "new-session", "-d", "-s", $SESSION -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 4

# Check session is running
$sessions = & $PSMUX ls 2>&1 | Out-String
Check "Session '$SESSION' started" ($sessions -match $SESSION)

if ($sessions -match $SESSION) {
    # ------ Test key bindings from plugins ------
    Write-Host "`n  Checking key bindings..." -ForegroundColor Cyan
    $keys = & $PSMUX list-keys -t $SESSION 2>&1 | Out-String
    
    # psmux-sensible bindings
    Check "sensible: R binding (reload)" ($keys -match '\bR\b.*source-file|source')
    Check "sensible: | binding (hsplit)" ($keys -match '\|\s.*split-window')
    Check "sensible: - binding (vsplit)" ($keys -match '\-\s.*split-window')
    Check "sensible: S-Left (prev window)" ($keys -match 'S-Left|ShiftLeft.*previous-window')
    Check "sensible: S-Right (next window)" ($keys -match 'S-Right|ShiftRight.*next-window')
    
    # psmux-pain-control bindings
    Check "pain-control: h binding (select-pane -L)" ($keys -match '\bh\b.*select-pane.*-L')
    Check "pain-control: j binding (select-pane -D)" ($keys -match '\bj\b.*select-pane.*-D')
    Check "pain-control: k binding (select-pane -U)" ($keys -match '\bk\b.*select-pane.*-U')
    Check "pain-control: l binding (select-pane -R)" ($keys -match '\bl\b.*select-pane.*-R')
    Check "pain-control: M-h (resize-pane)" ($keys -match 'M-h.*resize-pane')
    Check "pain-control: c binding (new-window)" ($keys -match '\bc\b.*new-window')
    
    # psmux-resurrect bindings
    Check "resurrect: C-s (save)" ($keys -match 'C-s.*run-shell.*save')
    Check "resurrect: C-r (restore)" ($keys -match 'C-r.*run-shell.*restore')
    
    # psmux-logging bindings
    Check "logging: M-o (toggle)" ($keys -match 'M-o.*run-shell.*toggle_logging')
    Check "logging: M-p (screenshot)" ($keys -match 'M-p.*run-shell.*capture_screen')
    Check "logging: M-i (history)" ($keys -match 'M-i.*run-shell.*capture_history')
    
    # psmux-sidebar bindings
    Check "sidebar: Tab (toggle)" ($keys -match 'Tab.*run-shell.*toggle_sidebar')
    
    # psmux-battery bindings
    Check "battery: b (info)" ($keys -match '\bb\b.*run-shell.*battery')
    
    # psmux-cpu bindings
    Check "cpu: C-c (info)" ($keys -match 'C-c.*run-shell.*cpu')
    
    # ------ Test options from plugins and themes ------
    Write-Host "`n  Checking options..." -ForegroundColor Cyan
    $opts = & $PSMUX show-options -g -t $SESSION 2>&1 | Out-String
    
    # psmux-sensible options
    Check "sensible: mouse on" ($opts -match 'mouse\s+on')
    Check "sensible: mode-keys vi" ($opts -match 'mode-keys\s+vi')
    Check "sensible: base-index 1" ($opts -match 'base-index\s+1')
    Check "sensible: renumber-windows on" ($opts -match 'renumber-windows\s+on')
    Check "sensible: history-limit 50000" ($opts -match 'history-limit\s+50000')
    Check "sensible: focus-events on" ($opts -match 'focus-events\s+on')
    Check "sensible: display-time 2000" ($opts -match 'display-time\s+2000')
    Check "sensible: automatic-rename on" ($opts -match 'automatic-rename\s+on')
    
    # psmux-theme-gruvbox theme options (should be last applied)
    Check "gruvbox: status-style has bg=#3c3836" ($opts -match 'status-style.*bg=#3c3836')
    Check "gruvbox: status-left set" ($opts -match 'status-left\s')
    Check "gruvbox: status-right set" ($opts -match 'status-right\s')
    Check "gruvbox: pane-active-border-style" ($opts -match 'pane-active-border-style.*fg=#8ec07c')
    Check "gruvbox: message-style" ($opts -match 'message-style.*bg=#504945')
    Check "gruvbox: mode-style" ($opts -match 'mode-style.*bg=#fabd2f')
    Check "gruvbox: window-status-format" ($opts -match 'window-status-format')
    Check "gruvbox: window-status-current-format" ($opts -match 'window-status-current-format')
    
    # ------ Test hooks ------
    Write-Host "`n  Checking hooks..." -ForegroundColor Cyan
    $hooks = & $PSMUX show-hooks -t $SESSION 2>&1 | Out-String
    Check "continuum: client-attached hook" ($hooks -match 'client-attached.*auto_save')
    Check "battery: client-attached hook" ($hooks -match 'client-attached.*battery_status')
    Check "cpu: client-attached hook" ($hooks -match 'client-attached.*system_stats')
    
    # --- Kill test session ---
    & $PSMUX kill-session -t $SESSION 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Write-Host "  Test session killed." -ForegroundColor DarkGray
} else {
    Write-Host "  SKIPPING runtime tests - session failed to start" -ForegroundColor Red
}

# =============================================================================
# PHASE 4: Test each theme individually
# =============================================================================
Write-Host "`n--- Phase 4: Theme Loading Tests ---" -ForegroundColor Yellow

foreach ($theme in $themes) {
    $themeConf = Join-Path $PLUGIN_DIR "$theme\plugin.conf"
    if (-not (Test-Path $themeConf)) { continue }
    
    # Create config with just this theme
    $themeTestConf = @"
# Minimal config with theme: $theme
set -g escape-time 50
source-file $($themeConf -replace '\\','/')
"@
    Set-Content $origConfig $themeTestConf -Force
    
    $themeSession = "theme_test_$(Get-Random -Min 100 -Max 999)"
    $proc2 = Start-Process -FilePath $PSMUX -ArgumentList "new-session", "-d", "-s", $themeSession -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 3
    
    $themeSessions = & $PSMUX ls 2>&1 | Out-String
    if ($themeSessions -match $themeSession) {
        $themeOpts = & $PSMUX show-options -g -t $themeSession 2>&1 | Out-String
        
        # Every theme should set these
        Check "${theme}: sets status-style" ($themeOpts -match 'status-style\s+\S')
        Check "${theme}: sets status-left" ($themeOpts -match 'status-left\s')
        Check "${theme}: sets status-right" ($themeOpts -match 'status-right\s')
        Check "${theme}: sets pane-active-border-style" ($themeOpts -match 'pane-active-border-style\s')
        Check "${theme}: sets message-style" ($themeOpts -match 'message-style\s')
        Check "${theme}: sets mode-style" ($themeOpts -match 'mode-style\s')
        Check "${theme}: sets window-status-format" ($themeOpts -match 'window-status-format\s')
        Check "${theme}: sets window-status-current-format" ($themeOpts -match 'window-status-current-format\s')
        
        & $PSMUX kill-session -t $themeSession 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    } else {
        Check "${theme}: session starts" $false "Failed to start session with theme"
    }
}

# =============================================================================
# PHASE 5: Test .ps1 entry points syntax (don't execute, just parse)
# =============================================================================
Write-Host "`n--- Phase 5: PowerShell Script Syntax Check ---" -ForegroundColor Yellow

foreach ($plugin in ($plugins + $themes + @('ppm'))) {
    $ps1Path = Join-Path $PLUGIN_DIR "$plugin\$plugin.ps1"
    if (-not (Test-Path $ps1Path)) {
        # Try alternate names
        $ps1Path = Join-Path $PLUGIN_DIR "$plugin\ppm.ps1"
        if (-not (Test-Path $ps1Path)) { continue }
    }
    
    # Check syntax by tokenizing (doesn't execute)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($ps1Path, [ref]$tokens, [ref]$errors)
    
    Check "$plugin.ps1: valid PowerShell syntax" ($errors.Count -eq 0) $(if($errors.Count -gt 0){"$($errors.Count) syntax errors: $($errors[0].Message)"})
}

# Also check helper scripts
$allHelperScripts = Get-ChildItem -Path $PLUGIN_DIR -Include '*.ps1' -Recurse -File | 
    Where-Object { $_.FullName -notmatch '\\\.git\\' }
    
Write-Host "`n  Checking $($allHelperScripts.Count) total .ps1 files..." -ForegroundColor Cyan
foreach ($script in $allHelperScripts) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    
    $relPath = $script.FullName -replace [regex]::Escape($PLUGIN_DIR + '\'), ''
    if ($errors.Count -gt 0) {
        Check "${relPath}: valid syntax" $false "$($errors.Count) errors: $($errors[0].Message)"
    }
    # Only report failures for syntax, don't flood with passes
}
Write-Host "  All .ps1 files parsed for syntax errors." -ForegroundColor DarkGray

# =============================================================================
# Cleanup
# =============================================================================
Write-Host "`n--- Cleanup ---" -ForegroundColor Yellow

# Kill any remaining test sessions
& $PSMUX kill-server 2>&1 | Out-Null

# Restore original config
if ($hadConfig) {
    Copy-Item $backupConfig $origConfig -Force
    Remove-Item $backupConfig -Force -ErrorAction SilentlyContinue
    Write-Host "  Restored original config." -ForegroundColor DarkGray
} else {
    Remove-Item $origConfig -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed test config." -ForegroundColor DarkGray
}
Remove-Item $testConfig -Force -ErrorAction SilentlyContinue

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "  RESULTS: $pass PASS, $fail FAIL, $warn WARN" -ForegroundColor $(if($fail -gt 0){'Red'}elseif($warn -gt 0){'Yellow'}else{'Green'})
Write-Host "========================================" -ForegroundColor Magenta

if ($fail -gt 0) {
    Write-Host "`nFailed tests:" -ForegroundColor Red
    $results | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
        Write-Host "  - $($_.Test)$(if($_.Detail){": $($_.Detail)"})" -ForegroundColor Red
    }
}

if ($warn -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $results | Where-Object { $_.Result -eq 'WARN' } | ForEach-Object {
        Write-Host "  - $($_.Test)$(if($_.Detail){": $($_.Detail)"})" -ForegroundColor Yellow
    }
}

Write-Host ""
exit $fail


