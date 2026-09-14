#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect: unnamed session policy (@resurrect-save-unnamed, issue #37)
# and the collapsed "still running" restore report (issue #35)
# =============================================================================
# Runs against the real psmux binary in a private data root (PSMUX_DATA_DIR)
# with USERPROFILE redirected, so it never touches the developer's own server
# or ~/.psmux/resurrect.
#
# Covers:
#   auto (default)  an untouched auto-named session (one window, one pane,
#                   idle shell) is not saved; a shaped one (split pane) is;
#                   named sessions are; __internal names never are.
#   on              every auto-named session is saved (tmux-resurrect parity)
#   off             no auto-named session is saved
#   all filtered    save exits 0 with an explicit "nothing to save" line and
#                   does not repoint 'last'
#   restore         with every saved session still alive, restore prints one
#                   "still running" line (not one per session) and a summary
#                   that says nothing was restored and why
#   cold restore    after kill-server the save restores only what was kept,
#                   so the untouched '0' does not come back (the #37 loop)
# Run:  pwsh -File tests/test_resurrect_save_unnamed.ps1
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "  FAIL: $name$(if($detail){' >> ' + $detail})" -ForegroundColor Red; $script:fail++ }
}

$PLUGIN_ROOT    = Split-Path $PSScriptRoot -Parent
$SAVE_SCRIPT    = Join-Path $PLUGIN_ROOT 'psmux-resurrect\scripts\save.ps1'
$RESTORE_SCRIPT = Join-Path $PLUGIN_ROOT 'psmux-resurrect\scripts\restore.ps1'
$PSMUX = (Get-Command psmux -ErrorAction Stop).Source

Write-Host "`n=== psmux-resurrect @resurrect-save-unnamed test (isolated server) ===" -ForegroundColor Magenta

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("psmux-unnamed-{0}" -f ([guid]::NewGuid().ToString('N')))
$home    = Join-Path $sandbox 'home'
$data    = Join-Path $sandbox 'data'
New-Item -ItemType Directory -Path (Join-Path $home '.psmux\resurrect'), $data -Force | Out-Null

$savedUserProfile = $env:USERPROFILE
$savedDataDir     = $env:PSMUX_DATA_DIR
$env:USERPROFILE     = $home
$env:PSMUX_DATA_DIR  = $data
$env:PSMUX_ALLOW_NESTING = '1'
foreach ($v in 'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE') {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}

$lastFile = Join-Path $home '.psmux\resurrect\last'

function Wait-Session([string]$name) {
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        & $PSMUX has-session -t $name 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

function Invoke-Save { (& pwsh -NoProfile -File $SAVE_SCRIPT 2>&1 | Out-String) }
function Invoke-Restore { (& pwsh -NoProfile -File $RESTORE_SCRIPT 2>&1 | Out-String) }
function Get-SavedNames {
    if (-not (Test-Path $lastFile)) { return @() }
    $f = (Get-Content $lastFile -Raw).Trim()
    if (-not (Test-Path $f)) { return @() }
    return @((Get-Content $f -Raw | ConvertFrom-Json).sessions.name)
}
function Reset-Saves {
    Remove-Item (Join-Path $home '.psmux\resurrect\*') -Force -ErrorAction SilentlyContinue
}

try {
    # --- Fixture: 0 untouched, 1 shaped (split), work named, __internal ---
    & $PSMUX new-session -d 2>&1 | Out-Null                       # auto-named '0'
    Check "auto-named session 0 exists" (Wait-Session '0') ''
    & $PSMUX new-session -d 2>&1 | Out-Null                       # auto-named '1'
    Check "auto-named session 1 exists" (Wait-Session '1') ''
    & $PSMUX split-window -t '1' 2>&1 | Out-Null                  # shape it
    & $PSMUX new-session -d -s work -n editor 2>&1 | Out-Null
    Check "named session work exists" (Wait-Session 'work') ''
    & $PSMUX new-session -d -s __internal 2>&1 | Out-Null
    Check "internal session __internal exists" (Wait-Session '__internal') ''
    Start-Sleep -Milliseconds 500
    $panes1 = @((& $PSMUX list-panes -t '1' -F '#{pane_id}' 2>&1) | Where-Object { "$_" -match '^%\d+$' })
    Check "session 1 has two panes (shaped)" ($panes1.Count -eq 2) "Got: $($panes1.Count)"

    # --- auto (option unset) ---
    Write-Host "`n--- auto (default) ---" -ForegroundColor Yellow
    & $PSMUX set-option -gu '@resurrect-save-unnamed' 2>&1 | Out-Null
    $out = Invoke-Save
    $names = Get-SavedNames
    Check "auto: untouched 0 is not saved" ($names -notcontains '0') "Saved: [$($names -join ', ')]"
    Check "auto: shaped 1 is saved" ($names -contains '1') "Saved: [$($names -join ', ')]"
    Check "auto: named work is saved" ($names -contains 'work') "Saved: [$($names -join ', ')]"
    Check "auto: __internal is never saved" ($names -notcontains '__internal') "Saved: [$($names -join ', ')]"
    Check "auto: save output names what it skipped" ($out -match 'not saving 0 \(unnamed, untouched\)') "Output: $out"

    # --- on ---
    Write-Host "`n--- on ---" -ForegroundColor Yellow
    Reset-Saves
    & $PSMUX set-option -g '@resurrect-save-unnamed' 'on' 2>&1 | Out-Null
    $null = Invoke-Save
    $names = Get-SavedNames
    Check "on: untouched 0 is saved" ($names -contains '0') "Saved: [$($names -join ', ')]"
    Check "on: shaped 1 is saved" ($names -contains '1') "Saved: [$($names -join ', ')]"
    Check "on: __internal is still never saved" ($names -notcontains '__internal') "Saved: [$($names -join ', ')]"

    # --- off ---
    Write-Host "`n--- off ---" -ForegroundColor Yellow
    Reset-Saves
    & $PSMUX set-option -g '@resurrect-save-unnamed' 'off' 2>&1 | Out-Null
    $null = Invoke-Save
    $names = Get-SavedNames
    Check "off: untouched 0 is not saved" ($names -notcontains '0') "Saved: [$($names -join ', ')]"
    Check "off: shaped 1 is not saved either" ($names -notcontains '1') "Saved: [$($names -join ', ')]"
    Check "off: named work is saved" ($names -contains 'work') "Saved: [$($names -join ', ')]"

    # --- everything filtered: only unnamed sessions running ---
    Write-Host "`n--- all sessions filtered ---" -ForegroundColor Yellow
    Reset-Saves
    & $PSMUX kill-session -t work 2>&1 | Out-Null
    & $PSMUX kill-session -t __internal 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    # Options are (re)applied after the session set changes: psmux serves
    # `show-options -g` from the current session, and a session created after
    # a `set -g` does not see it.
    & $PSMUX set-option -g '@resurrect-save-unnamed' 'off' 2>&1 | Out-Null
    $out = Invoke-Save
    Check "all filtered: save exits with an explicit nothing-to-save line" ($out -match 'nothing to save, every running session was skipped') "Output: $out"
    Check "all filtered: no save file written, last not repointed" (-not (Test-Path $lastFile)) ''
    Check "all filtered: does not claim the server is down" ($out -notmatch 'server likely down') "Output: $out"

    # --- restore report while everything saved is still alive (#35) ---
    Write-Host "`n--- restore with saved sessions still running ---" -ForegroundColor Yellow
    & $PSMUX new-session -d -s work -n editor 2>&1 | Out-Null
    Wait-Session 'work' | Out-Null
    & $PSMUX set-option -g '@resurrect-save-unnamed' 'on' 2>&1 | Out-Null
    $null = Invoke-Save
    $names = Get-SavedNames
    Check "fixture: 0, 1 and work saved with unnamed on" (($names -contains '0') -and ($names -contains '1') -and ($names -contains 'work')) "Saved: [$($names -join ', ')]"
    $out = Invoke-Restore
    $skipLines = @(($out -split "`r?`n") | Where-Object { $_ -match 'Still running and complete, left alone' })
    Check "restore: one collapsed line for every skipped session" ($skipLines.Count -eq 1) "Output: $out"
    Check "restore: no per-session already-exists lines" ($out -notmatch "already exists, skipping") "Output: $out"
    Check "restore: the collapsed line names the sessions" ($skipLines[0] -match '\b0\b' -and $skipLines[0] -match '\bwork\b') "Line: $($skipLines[0])"
    Check "restore: tells the user how to attach or overwrite" ($out -match 'psmux attach -t' -and $out -match '@resurrect-overwrite') "Output: $out"
    Check "restore: header names the save file" ($out -match 'restoring 3 sessions from psmux_resurrect_') "Output: $out"
    $status = (& $PSMUX show-options -gv '@resurrect-status' 2>&1 | Out-String).Trim()
    Check "restore: status option cleared after summary" (-not $status -or $status -match 'unknown option|not found|error') "Status: $status"

    # --- the #37 loop: cold restore must not bring the untouched 0 back ---
    Write-Host "`n--- cold restore after kill-server (auto) ---" -ForegroundColor Yellow
    Reset-Saves
    & $PSMUX set-option -gu '@resurrect-save-unnamed' 2>&1 | Out-Null
    $null = Invoke-Save
    $names = Get-SavedNames
    Check "auto save before kill: 1 and work only" (($names -notcontains '0') -and ($names -contains '1') -and ($names -contains 'work')) "Saved: [$($names -join ', ')]"
    & $PSMUX kill-server 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    $out = Invoke-Restore
    Start-Sleep -Milliseconds 500
    $live = @((& $PSMUX list-sessions -F '#{session_name}' 2>&1) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch 'no server' })
    Check "cold restore: work came back" ($live -contains 'work') "Live: [$($live -join ', ')]"
    Check "cold restore: shaped 1 came back" ($live -contains '1') "Live: [$($live -join ', ')]"
    Check "cold restore: untouched 0 did not come back" ($live -notcontains '0') "Live: [$($live -join ', ')]"
    $panes1 = @((& $PSMUX list-panes -t '1' -F '#{pane_id}' 2>&1) | Where-Object { "$_" -match '^%\d+$' })
    Check "cold restore: 1 has its split again" ($panes1.Count -eq 2) "Got: $($panes1.Count)"
    $null = Invoke-Save
    $names = Get-SavedNames
    Check "save after cold restore still has no 0 (loop broken)" ($names -notcontains '0') "Saved: [$($names -join ', ')]"
}
finally {
    & $PSMUX kill-server 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    $env:USERPROFILE    = $savedUserProfile
    if ($null -ne $savedDataDir) { $env:PSMUX_DATA_DIR = $savedDataDir } else { Remove-Item Env:PSMUX_DATA_DIR -ErrorAction SilentlyContinue }
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Magenta
Write-Host "  @resurrect-save-unnamed" -ForegroundColor Magenta
Write-Host "  PASS: $pass  FAIL: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
Write-Host "======================================" -ForegroundColor Magenta
if ($fail -gt 0) { exit 1 }
exit 0
