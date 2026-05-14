#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect: End-to-end strategy wiring test
#
# Validates that restore.ps1 actually invokes Get-StrategyCommand for each
# restored pane and routes the strategy's stdout into `send-keys`.
#
# Isolation strategy: copy save.ps1/restore.ps1/strategy.ps1 + strategies/
# to a temp plugin dir, monkey-patch Get-PsmuxBin in the copies so $PSMUX
# becomes a pwsh wrapper that scrubs PSMUX_SESSION (to avoid nesting) and
# injects -L <socket> on every call. All psmux traffic from the patched
# scripts routes to an isolated server, leaving the user's default server
# untouched.
#
# We use 'shell' as the strategy key because that's what psmux's
# pane_current_command returns for idle shells on Windows. (Confirmed
# against real save data; same reason copilot panes report as 'node' rather
# than 'copilot'.)
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL: $name >> $detail" -ForegroundColor Red; $script:fail++ }
}

$PLUGIN_ROOT = Split-Path $PSScriptRoot -Parent
$PLUGIN_DIR  = Join-Path $PLUGIN_ROOT 'psmux-resurrect'
$realPsmux   = (Get-Command psmux -ErrorAction Stop).Source
$socketName  = 'resurrect_e2e'

$tempRoot = Join-Path $env:TEMP "psmux_resurrect_e2e_$([guid]::NewGuid().ToString('N'))"
$tempPlugin = Join-Path $tempRoot 'plugin-root\psmux-resurrect'
New-Item -ItemType Directory -Path $tempPlugin -Force | Out-Null
Copy-Item -Recurse (Join-Path $PLUGIN_DIR 'scripts')    $tempPlugin -Force
Copy-Item -Recurse (Join-Path $PLUGIN_DIR 'strategies') $tempPlugin -Force

$saveDir = Join-Path $tempRoot 'save'
New-Item -ItemType Directory -Path $saveDir -Force | Out-Null

# Isolated config: pre-sets the strategy options at config-source time.
# This is the path that mirrors production - psmux applies these globally
# to every new session, so restore.ps1 can still read them after creating
# the 'target' session. Runtime `set-option -g` only attaches to the
# current session and doesn't propagate, which is why we don't use it.
$saveDirEsc = $saveDir.Replace("'", "''")
$confFile = Join-Path $tempRoot 'test.psmux.conf'
@"
set -g @resurrect-strategy-shell 'e2etest'
set -g @resurrect-dir '$saveDirEsc'
set -g @resurrect-processes 'shell'
"@ | Set-Content $confFile -Encoding ASCII

# Env-stripping wrapper that also loads the test config. -f is honored at
# server startup; subsequent invocations ignore it but still target the
# right socket.
$wrapperPath = Join-Path $tempRoot 'psmux-wrapper.ps1'
@"
Remove-Item Env:PSMUX_SESSION -ErrorAction SilentlyContinue
Remove-Item Env:PSMUX_TARGET_SESSION -ErrorAction SilentlyContinue
Remove-Item Env:TMUX -ErrorAction SilentlyContinue
Remove-Item Env:TMUX_PANE -ErrorAction SilentlyContinue
& '$realPsmux' -f '$confFile' -L $socketName @args
exit `$LASTEXITCODE
"@ | Set-Content -Path $wrapperPath -Encoding UTF8

# Patch Get-PsmuxBin in the copies to use the wrapper.
$wrapperEsc = $wrapperPath.Replace("'", "''")
$replacement = "function Get-PsmuxBin { '$wrapperEsc' }"
foreach ($rel in @('scripts\save.ps1','scripts\restore.ps1')) {
    $f = Join-Path $tempPlugin $rel
    $c = Get-Content $f -Raw
    $patched = [regex]::Replace($c, '(?ms)^function Get-PsmuxBin \{.*?^\}', $replacement)
    if ($patched -eq $c) { throw "patch failed: $f" }
    Set-Content -Path $f -Value $patched -NoNewline -Encoding UTF8
}

# Sentinel + test strategy
$sentinel   = Join-Path $env:TEMP "psmux_strategy_invoked_$([guid]::NewGuid().ToString('N')).txt"
$echoMarker = "RESTORED_MARKER_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$strategyFile = Join-Path $tempPlugin 'strategies\shell_e2etest.ps1'
@"
param([string]`$OriginalCommand, [string]`$Directory)
"sentinel hit at `$(Get-Date -Format o); cmd=[`$OriginalCommand]; dir=[`$Directory]" |
    Add-Content -Path '$sentinel' -Encoding UTF8
"echo $echoMarker"
"@ | Set-Content -Path $strategyFile -Encoding UTF8

Write-Host "=== psmux-resurrect E2E Strategy Wiring ===" -ForegroundColor Magenta
Write-Host "wrapper  : $wrapperPath"
Write-Host "conf     : $confFile"
Write-Host "sentinel : $sentinel"
Write-Host "marker   : $echoMarker"
Write-Host "strategy : $strategyFile"
Write-Host "plugin   : $tempPlugin"
Write-Host "save dir : $saveDir"

try {
    $subScript = @'
param(
    [string]$wrapperPath, [string]$tempPlugin, [string]$saveDir, [string]$sentinel,
    [string]$echoMarker, [string]$realPsmux, [string]$socket
)
$ErrorActionPreference = 'Continue'
function w { param([Parameter(ValueFromRemainingArguments)]$a) & $wrapperPath @a }

# Wipe any prior isolated server
w kill-server 2>&1 | Out-Null
Start-Sleep 1

# Bootstrap: create `keep` (placeholder) and `target` (unit under test).
# Server-startup config-source applies the strategy options to all new
# sessions automatically; no runtime set-option needed.
function ensure-session {
    param([string]$name)
    for ($i = 0; $i -lt 5; $i++) {
        w new-session -d -s $name -c $env:USERPROFILE 2>&1 | Out-Null
        Start-Sleep 2
        $listed = (w list-sessions -F '#{session_name}' 2>&1 | Out-String).Trim() -split "`r?`n"
        if ($listed -contains $name) { return $true }
    }
    return $false
}
$keepOk   = ensure-session 'keep'
$targetOk = ensure-session 'target'
Write-Host "  bootstrap: keep=$keepOk target=$targetOk"
$sessList = (w list-sessions -F '#{session_name}' 2>&1 | Out-String).Trim()
Write-Host "  sessions after bootstrap -> [$sessList]"
if (-not ($keepOk -and $targetOk)) { throw "bootstrap failed" }

$strat = (w show-options -gv '@resurrect-strategy-shell' 2>&1 | Out-String).Trim()
Write-Host "  @resurrect-strategy-shell (from conf) -> [$strat]"
$dirOpt = (w show-options -gv '@resurrect-dir' 2>&1 | Out-String).Trim()
Write-Host "  @resurrect-dir (from conf) -> [$dirOpt]"

$pc = (w list-panes -t 'target:0' -F '#{pane_current_command}' 2>&1 | Out-String).Trim()
Write-Host "  pane_current_command of target -> [$pc]"

# Save (patched scripts route through wrapper)
$saveOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tempPlugin 'scripts\save.ps1') 2>&1 | Out-String
Write-Host "  save.ps1 output: $($saveOut.Trim())"

$lastFile = Join-Path $saveDir 'last'
$savedFile = if (Test-Path $lastFile) { (Get-Content $lastFile -Raw).Trim() } else { '' }
Write-Host "  save file -> $savedFile"

$savedSessNames = ''; $savedTargetPaneCmd = $null; $savedTargetPaneDir = $null
if ($savedFile -and (Test-Path $savedFile)) {
    $saved = Get-Content $savedFile -Raw | ConvertFrom-Json
    $savedSessNames = ($saved.sessions | ForEach-Object name) -join ','
    Write-Host "  saved sessions -> [$savedSessNames]"
    $tgt = $saved.sessions | Where-Object name -EQ 'target' | Select-Object -First 1
    if ($tgt) {
        $savedTargetPaneCmd = $tgt.windows[0].panes[0].command
        $savedTargetPaneDir = $tgt.windows[0].panes[0].directory
        Write-Host "  target pane: cmd=[$savedTargetPaneCmd] dir=[$savedTargetPaneDir]"
    }
}

# Kill only `target`. `keep` keeps the server alive; the strategy options
# came from the config so they propagate to new sessions created by restore.
w kill-session -t target 2>&1 | Out-Null
Start-Sleep 1
$afterKill = (w list-sessions -F '#{session_name}' 2>&1 | Out-String).Trim()
Write-Host "  sessions after kill-session target -> [$afterKill]"

# UNIT UNDER TEST: restore.ps1 must invoke Get-StrategyCommand for the
# 'target' pane (whose saved command is 'shell') and route the strategy's
# stdout into send-keys.
$restoreOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tempPlugin 'scripts\restore.ps1') 2>&1 | Out-String
Write-Host "  restore.ps1 output:"
Write-Host $restoreOut
# Give the restored pane time for its shell to come up and echo the strategy's text
Start-Sleep 8

$restored = (w list-sessions -F '#{session_name}' 2>&1 | Out-String).Trim()
Write-Host "  sessions after restore -> [$restored]"

# Use direct wrapper call to avoid the -p / -ProgressAction collision in pwsh
# parameter binding for the `w` function.
$captured = (& $wrapperPath capture-pane -p -t 'target:0' 2>&1 | Out-String)
Write-Host "  --- captured pane content (len=$($captured.Length)) ---"
Write-Host $captured
Write-Host "  --- end capture ---"

Write-Host "<<<PAYLOAD_START>>>"
[PSCustomObject]@{
    PaneCommand           = $pc
    SavedSessions         = $savedSessNames
    SavedTargetPaneCmd    = $savedTargetPaneCmd
    SavedTargetPaneDir    = $savedTargetPaneDir
    SessionsAfterKill     = $afterKill
    SessionsAfterRestore  = $restored
    SentinelExists        = Test-Path $sentinel
    SentinelContent       = if (Test-Path $sentinel) { Get-Content $sentinel -Raw } else { '' }
    PaneCaptured          = $captured
} | ConvertTo-Json -Depth 4 -Compress
Write-Host ""
Write-Host "<<<PAYLOAD_END>>>"
'@

    $runner = Join-Path $tempRoot 'runner.ps1'
    Set-Content -Path $runner -Value $subScript -Encoding UTF8

    $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runner `
        $wrapperPath $tempPlugin $saveDir $sentinel $echoMarker $realPsmux $socketName 2>&1
    $resultText = ($result | Out-String)
    Write-Host "`n--- Subprocess output ---" -ForegroundColor Cyan
    Write-Host $resultText
    Write-Host "--- End subprocess output ---" -ForegroundColor Cyan

    $payload = $null
    if ($resultText -match '(?s)<<<PAYLOAD_START>>>\s*(\{.*?\})\s*<<<PAYLOAD_END>>>') {
        try { $payload = $Matches[1] | ConvertFrom-Json } catch {
            Write-Host "  payload JSON parse failed: $_" -ForegroundColor Red
        }
    }

    Check "subprocess emitted JSON payload" ($payload -ne $null) ''
    if ($payload) {
        Check "save captured 'target' session" `
            ($payload.SavedSessions -match '\btarget\b') "Got: [$($payload.SavedSessions)]"

        Check "save captured 'keep' session" `
            ($payload.SavedSessions -match '\bkeep\b') "Got: [$($payload.SavedSessions)]"

        Check "target killed before restore" `
            ($payload.SessionsAfterKill -notmatch '\btarget\b') "Got: [$($payload.SessionsAfterKill)]"

        Check "restore re-created 'target'" `
            ($payload.SessionsAfterRestore -match '\btarget\b') "Got: [$($payload.SessionsAfterRestore)]"

        Check "strategy script was invoked by restore.ps1 (sentinel exists)" `
            $payload.SentinelExists "Sentinel: $sentinel"

        Check "sentinel records the original command" `
            ($payload.SentinelContent -match 'cmd=\[shell\]') "Got: [$($payload.SentinelContent)]"

        Check "sentinel records the pane directory" `
            ($payload.SentinelContent -match [regex]::Escape($env:USERPROFILE)) "Got: [$($payload.SentinelContent)]"

        Check "strategy stdout was send-keys'd to the restored pane" `
            ($payload.PaneCaptured -match [regex]::Escape($echoMarker)) `
            "Looking for [$echoMarker] in capture"
    }
}
finally {
    if (Test-Path $wrapperPath) {
        & pwsh -NoProfile -File $wrapperPath kill-server 2>&1 | Out-Null
    }
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $sentinel -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Magenta
Write-Host "  E2E Strategy Wiring" -ForegroundColor Magenta
Write-Host "  PASS: $pass  FAIL: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
Write-Host "======================================" -ForegroundColor Magenta

if ($fail -gt 0) { exit 1 }
exit 0
