#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect: @resurrect-overwrite option regression test (issue #29)
# =============================================================================
# Hermetic by design: needs NEITHER a running psmux server NOR a real psmux
# binary. A fake-psmux shim simulates a session that is already running (or
# not), and logs every command it's called with to a file so this test can
# assert the exact sequence of calls restore.ps1 makes, without needing real
# session/pane state. $env:USERPROFILE is redirected to a temp dir so this
# never touches a real dev's ~/.psmux/resurrect.
#
# Covers:
#   - @resurrect-overwrite unset (default off): existing session is left
#     alone -- no kill-session, no new-session, counted as skipped.
#   - @resurrect-overwrite 'on', session exists: kill-session runs BEFORE
#     new-session (order matters -- recreating before the kill lands would
#     silently no-op), counted as overwritten.
#   - @resurrect-overwrite 'on', session does NOT exist: no kill-session call
#     at all (nothing to kill), still restored normally, not counted as
#     overwritten.
# Run:  pwsh -File tests/test_resurrect_overwrite.ps1
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "  FAIL: $name$(if($detail){' >> ' + $detail})" -ForegroundColor Red; $script:fail++ }
}

$PLUGIN_ROOT = Split-Path $PSScriptRoot -Parent
$RESTORE_SCRIPT = Join-Path $PLUGIN_ROOT 'psmux-resurrect\scripts\restore.ps1'

Write-Host "`n=== psmux-resurrect @resurrect-overwrite test (hermetic) ===" -ForegroundColor Magenta

$sandbox   = Join-Path ([IO.Path]::GetTempPath()) ("psmux-overwrite-{0}" -f ([guid]::NewGuid().ToString('N')))
$resurrect = Join-Path $sandbox '.psmux\resurrect'
$binDir    = Join-Path $sandbox 'bin'
$stateDir  = Join-Path $sandbox 'state'
New-Item -ItemType Directory -Path $resurrect, $binDir, $stateDir -Force | Out-Null

$logFile         = Join-Path $stateDir 'calls.log'
$sessionAliveFlag = Join-Path $stateDir 'session_alive'
$overwriteOptFile = Join-Path $stateDir 'overwrite_opt'

# Saved environment: one session, one window, one pane. Minimal on purpose --
# this test is about the exists/overwrite decision, not restore mechanics
# (those are covered by the E2E and %id-targeting tests elsewhere).
$saveJson = @'
{
  "version": 2,
  "timestamp": "20260101_000000",
  "sessions": [
    { "name": "ow_test_session", "windows": [
      { "index": 0, "name": "main", "active": true, "layout": "abcd,80x24,0,0,1", "zoomed": false, "flags": "",
        "panes": [ { "index": 0, "directory": "C:/", "active": true, "title": "", "command": "pwsh" } ] }
    ] }
  ]
}
'@
$saveFile = Join-Path $resurrect 'psmux_resurrect_20260101_000000.json'
$saveJson | Set-Content $saveFile -Encoding UTF8
$saveFile | Set-Content (Join-Path $resurrect 'last') -Encoding UTF8

# --- fake psmux shim ---------------------------------------------------
# Resolved via PATHEXT as a .ps1 (not a .cmd bridge) so `-F '#{...}'` format
# strings with '|' survive intact -- same reasoning as test_resurrect_guard.ps1.
$shimPath = Join-Path $binDir 'psmux.ps1'
$shimBody = @"
`$logFile = '$logFile'
`$aliveFlag = '$sessionAliveFlag'
`$overwriteOptFile = '$overwriteOptFile'
`$a = `$args
Add-Content -Path `$logFile -Value (`$a -join ' ')

switch (`$a[0]) {
    'has-session' { if (Test-Path `$aliveFlag) { exit 0 } else { exit 1 } }
    'kill-session' { Remove-Item `$aliveFlag -Force -ErrorAction SilentlyContinue; exit 0 }
    'new-session' { New-Item -ItemType File -Path `$aliveFlag -Force | Out-Null; '%1'; exit 0 }
    'new-window' { '%2'; exit 0 }
    'split-window' { '%3'; exit 0 }
    'show-options' {
        if (`$a -contains '@resurrect-overwrite') {
            if (Test-Path `$overwriteOptFile) { (Get-Content `$overwriteOptFile -Raw).Trim(); exit 0 }
            exit 1
        }
        exit 1
    }
    default { exit 0 }
}
"@
Set-Content $shimPath $shimBody -Encoding UTF8

function Invoke-Restore {
    $u = $env:USERPROFILE; $p = $env:PATH; $x = $env:PATHEXT
    try {
        $env:USERPROFILE = $sandbox
        $env:PATH = "$binDir;$env:PATH"
        $env:PATHEXT = ".PS1;$env:PATHEXT"
        & pwsh -NoProfile -File $RESTORE_SCRIPT *>$null
    }
    finally { $env:USERPROFILE = $u; $env:PATH = $p; $env:PATHEXT = $x }
}

function Reset-Calls {
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
}
function Get-Calls { if (Test-Path $logFile) { Get-Content $logFile } else { @() } }

try {
    # --- 1. overwrite unset (default off), session exists -> skip, no kill/new-session ---
    Remove-Item $overwriteOptFile -Force -ErrorAction SilentlyContinue
    New-Item -ItemType File -Path $sessionAliveFlag -Force | Out-Null
    Reset-Calls
    Invoke-Restore
    $calls = Get-Calls
    Check "default (no option set): no kill-session call" (-not ($calls | Where-Object { $_ -like 'kill-session*' }))
    Check "default (no option set): no new-session call (session left alone)" (-not ($calls | Where-Object { $_ -like 'new-session*' }))
    Check "default (no option set): session still marked alive" (Test-Path $sessionAliveFlag)

    # --- 2. overwrite 'on', session exists -> kill-session BEFORE new-session ---
    'on' | Set-Content $overwriteOptFile -Encoding UTF8
    New-Item -ItemType File -Path $sessionAliveFlag -Force | Out-Null
    Reset-Calls
    Invoke-Restore
    $calls = Get-Calls
    $killIdx = 0; $newIdx = 0
    for ($i = 0; $i -lt $calls.Count; $i++) {
        if ($calls[$i] -like 'kill-session*' -and $killIdx -eq 0) { $killIdx = $i + 1 }
        if ($calls[$i] -like 'new-session*' -and $newIdx -eq 0) { $newIdx = $i + 1 }
    }
    Check "overwrite=on, session exists: kill-session was called" ($killIdx -gt 0) "calls=$($calls -join ' | ')"
    Check "overwrite=on, session exists: new-session was called" ($newIdx -gt 0) "calls=$($calls -join ' | ')"
    Check "overwrite=on, session exists: kill-session happens before new-session" ($killIdx -gt 0 -and $newIdx -gt 0 -and $killIdx -lt $newIdx) "kill@$killIdx new@$newIdx"

    # --- 3. overwrite 'on', session does NOT exist -> no kill-session call at all ---
    'on' | Set-Content $overwriteOptFile -Encoding UTF8
    Remove-Item $sessionAliveFlag -Force -ErrorAction SilentlyContinue
    Reset-Calls
    Invoke-Restore
    $calls = Get-Calls
    Check "overwrite=on, session absent: no kill-session call (nothing to kill)" (-not ($calls | Where-Object { $_ -like 'kill-session*' }))
    Check "overwrite=on, session absent: new-session was still called (fresh restore)" ($calls | Where-Object { $_ -like 'new-session*' })
}
finally {
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
