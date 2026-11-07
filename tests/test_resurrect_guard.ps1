#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect: empty-snapshot guard regression test (PR1)
# =============================================================================
# Hermetic by design: needs NEITHER a running psmux server NOR a real psmux
# binary. A fake-psmux shim simulates "server up" / "server down" / "partial",
# and $env:USERPROFILE is redirected to a temp dir, so this NEVER touches a real
# dev's ~/.psmux/resurrect (unlike test_resurrect*.ps1, which wipe it).
#
# Covers the save.ps1 0-session guard:
#   - server down (0 sessions): no snapshot written, `last` preserved byte-identical
#     (both with a prior good `last` and on a virgin dir -> guard, not dedup).
#   - server up (>=1 session): still writes + repoints (no false skip).
#   - partial capture: an enumerated session returns no panes, so the prior
#     snapshot and 'last' survive the failed capture.
# (The continuum break-on-empty / here-string drift asserts live in
#  test_continuum_guard.ps1 so this file stays green on the resurrect-only PR branch.)
# Run:  pwsh -File tests/test_resurrect_guard.ps1
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "  FAIL: $name$(if($detail){' >> ' + $detail})" -ForegroundColor Red; $script:fail++ }
}

$PLUGIN_ROOT = Split-Path $PSScriptRoot -Parent
$SAVE_SCRIPT = Join-Path $PLUGIN_ROOT 'psmux-resurrect\scripts\save.ps1'

Write-Host "`n=== psmux-resurrect empty-snapshot guard test (hermetic) ===" -ForegroundColor Magenta

# --- sandbox + fake-psmux shim ---------------------------------------------
$sandbox   = Join-Path ([IO.Path]::GetTempPath()) ("psmux-guard-{0}" -f ([guid]::NewGuid().ToString('N')))
$resurrect = Join-Path $sandbox '.psmux\resurrect'
$binDir    = Join-Path $sandbox 'bin'
New-Item -ItemType Directory -Path $resurrect, $binDir -Force | Out-Null
# Fake psmux is a .ps1 resolved via PATHEXT (NOT a .cmd bridge): a cmd `%*` bridge would
# let cmd interpret the `|` in psmux's `-F '#{...}|#{...}'` format strings as a pipe and
# mangle list-windows/list-panes. Invoke-Save adds .PS1 to PATHEXT so `Get-Command psmux`
# (in save.ps1's Get-PsmuxBin) resolves psmux.ps1 and args pass through PowerShell intact.

function Set-FakePsmux([ValidateSet('down','up','partial')][string]$Mode) {
    $impl = Join-Path $binDir 'psmux.ps1'
    switch ($Mode) {
        'down' { Set-Content $impl 'exit 0' -Encoding UTF8 }   # exit 0 + empty == no server (real psmux behaviour)
        'up'   { Set-Content $impl @'
$a = $args
if ($a[0] -eq 'list-sessions') { 'alpha'; exit 0 }
if ($a[0] -eq 'list-panes') {
    $row = (@(0, 'main', 1, 'c2be,80x24,0,0,1', 0, '', 0, 'C:\Users\Public', 1, 'title', 1234, 'pwsh') | ForEach-Object { ([string]$_).Replace('\', '\\') }) -join "`t"
    [Console]::Write($row + "`n")
    exit 0
}
exit 0
'@ -Encoding UTF8 }
        'partial' { Set-Content $impl @'
$a = $args
if ($a[0] -eq 'list-sessions') { 'alpha'; 'beta'; exit 0 }
if ($a[0] -eq 'list-panes') {
    if ($a -contains 'beta') { exit 0 }
    $row = (@(0, 'main', 1, 'c2be,80x24,0,0,1', 0, '', 0, 'C:\Users\Public', 1, 'title', 1234, 'pwsh') | ForEach-Object { ([string]$_).Replace('\', '\\') }) -join "`t"
    [Console]::Write($row + "`n")
    exit 0
}
exit 0
'@ -Encoding UTF8 }
    }
}
function Invoke-Save {
    $u = $env:USERPROFILE; $p = $env:PATH; $x = $env:PATHEXT
    try {
        $env:USERPROFILE = $sandbox
        $env:PATH = "$binDir;$env:PATH"
        $env:PATHEXT = ".PS1;$env:PATHEXT"   # so Get-Command psmux resolves psmux.ps1
        $invocation = "function Start-Sleep {}; & '$($SAVE_SCRIPT.Replace("'", "''"))'"
        & pwsh -NoProfile -Command $invocation *>$null
    }
    finally { $env:USERPROFILE = $u; $env:PATH = $p; $env:PATHEXT = $x }
}
function SnapCount { @(Get-ChildItem $resurrect -Filter 'psmux_resurrect_*.json' -ErrorAction SilentlyContinue).Count }
function Reset-GoodLast {
    Get-ChildItem $resurrect -File -ErrorAction SilentlyContinue | Remove-Item -Force
    $good = Join-Path $resurrect 'psmux_resurrect_20260101_120000.json'
    '{ "version":2, "timestamp":"20260101_120000", "sessions":[{"name":"real","windows":[]}] }' | Set-Content $good -Encoding UTF8
    $good | Set-Content (Join-Path $resurrect 'last') -Encoding UTF8
}

try {
    # 1. server DOWN, a good `last` exists -> must skip + preserve last
    Reset-GoodLast
    Set-FakePsmux 'down'
    $before = SnapCount
    $lastBefore = Get-Content (Join-Path $resurrect 'last') -Raw
    Invoke-Save
    Check "0-session capture writes no new snapshot" ((SnapCount) -eq $before) "before=$before after=$(SnapCount)"
    Check "0-session capture preserves 'last' (byte-identical)" ((Get-Content (Join-Path $resurrect 'last') -Raw) -ceq $lastBefore)

    # 2. server DOWN, virgin dir (no prior last) -> still no write (guard, not dedup)
    Get-ChildItem $resurrect -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Set-FakePsmux 'down'
    Invoke-Save
    Check "0-session on a virgin dir writes nothing (guard, not dedup)" ((SnapCount) -eq 0)
    Check "0-session on a virgin dir creates no 'last'" (-not (Test-Path (Join-Path $resurrect 'last')))

    # 3. positive control: a session exists -> must write + repoint last
    Reset-GoodLast
    Set-FakePsmux 'up'
    $before = SnapCount
    Invoke-Save
    Check "live session still writes a snapshot (no false skip)" ((SnapCount) -eq ($before + 1))

    Reset-GoodLast
    Set-FakePsmux 'partial'
    $before = SnapCount
    $lastBefore = Get-Content (Join-Path $resurrect 'last') -Raw
    Invoke-Save
    Check "partial capture writes no new snapshot" ((SnapCount) -eq $before)
    Check "partial capture preserves 'last' byte-identically" `
        ((Get-Content (Join-Path $resurrect 'last') -Raw) -ceq $lastBefore)
}
finally {
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
