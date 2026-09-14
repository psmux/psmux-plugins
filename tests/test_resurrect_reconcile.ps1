#!/usr/bin/env pwsh
# =============================================================================
# psmux-resurrect: restore into a running session (PR #36)
# =============================================================================
# Runs against the real psmux binary in a private data root (PSMUX_DATA_DIR)
# with USERPROFILE redirected, so it never touches the developer's own server
# or ~/.psmux/resurrect.
#
# Covers, with @resurrect-overwrite unset:
#   complete        a running session that still has every saved window is
#                   left alone and reported as such, not as restored
#   missing         windows killed after the save come back at their saved
#                   index with their name, split panes and layout, while the
#                   windows that were still there keep their pane ids
#   focus           adding windows does not move the running session's active
#                   window
#   report          one "Kept running session" line per session that got
#                   windows, the collapsed left-alone line for the rest, and a
#                   summary that counts both
# Run:  pwsh -File tests/test_resurrect_reconcile.ps1
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

Write-Host "`n=== psmux-resurrect reconcile test (isolated server) ===" -ForegroundColor Magenta

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("psmux-reconcile-{0}" -f ([guid]::NewGuid().ToString('N')))
$sbHome  = Join-Path $sandbox 'home'
$data    = Join-Path $sandbox 'data'
New-Item -ItemType Directory -Path (Join-Path $sbHome '.psmux\resurrect'), $data -Force | Out-Null

$savedUserProfile = $env:USERPROFILE
$savedDataDir     = $env:PSMUX_DATA_DIR
$env:USERPROFILE     = $sbHome
$env:PSMUX_DATA_DIR  = $data
$env:PSMUX_ALLOW_NESTING = '1'
foreach ($v in 'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE') {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}

function Wait-Session([string]$name) {
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        & $PSMUX has-session -t $name 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}
function Get-Windows([string]$session) {
    @((& $PSMUX list-windows -t $session -F '#{window_index}|#{window_name}|#{window_active}|#{window_panes}' 2>&1) |
        ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+\|' } | ForEach-Object {
            $p = $_ -split '\|'
            [PSCustomObject]@{ Index = [int]$p[0]; Name = $p[1]; Active = ($p[2] -eq '1'); Panes = [int]$p[3] }
        })
}
function Get-PaneIds([string]$target) {
    @((& $PSMUX list-panes -t $target -F '#{pane_id}' 2>&1) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^%\d+$' })
}

try {
    # --- fixture: work has editor(0), logs(1), build(2, split); done is one window ---
    & $PSMUX new-session -d -s work -n editor 2>&1 | Out-Null
    Check "fixture: session work up" (Wait-Session 'work') ''
    & $PSMUX new-window -t work -n logs 2>&1 | Out-Null
    & $PSMUX new-window -t work -n build 2>&1 | Out-Null
    & $PSMUX split-window -t 'work:2' 2>&1 | Out-Null
    & $PSMUX select-window -t 'work:0' 2>&1 | Out-Null
    & $PSMUX new-session -d -s done -n solo 2>&1 | Out-Null
    Check "fixture: session done up" (Wait-Session 'done') ''
    Start-Sleep -Milliseconds 500
    $before = Get-Windows 'work'
    Check "fixture: work has 3 windows, build split in 2" (($before.Count -eq 3) -and (($before | Where-Object Index -eq 2).Panes -eq 2)) "windows=$($before | ConvertTo-Json -Compress)"
    $editorPaneBefore = (Get-PaneIds 'work:0')[0]

    & $PSMUX set-option -g '@resurrect-save-unnamed' 'on' 2>&1 | Out-Null
    $null = & pwsh -NoProfile -File $SAVE_SCRIPT 2>&1
    $lastFile = Join-Path $sbHome '.psmux\resurrect\last'
    Check "fixture: save written" (Test-Path $lastFile) ''

    # --- kill logs and build after the save ---
    & $PSMUX kill-window -t 'work:2' 2>&1 | Out-Null
    & $PSMUX kill-window -t 'work:1' 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    $mid = Get-Windows 'work'
    Check "fixture: work down to editor only" (($mid.Count -eq 1) -and ($mid[0].Index -eq 0)) "windows=$($mid | ConvertTo-Json -Compress)"

    # --- restore with overwrite unset ---
    Write-Host "`n--- restore into running sessions ---" -ForegroundColor Yellow
    $out = (& pwsh -NoProfile -File $RESTORE_SCRIPT 2>&1 | Out-String)
    Start-Sleep -Milliseconds 500
    $after = Get-Windows 'work'
    Check "work has its 3 windows back" ($after.Count -eq 3) "windows=$($after | ConvertTo-Json -Compress)"
    $logs  = $after | Where-Object Index -eq 1
    $build = $after | Where-Object Index -eq 2
    Check "logs came back at index 1 with its name" ($logs -and $logs.Name -eq 'logs') "windows=$($after | ConvertTo-Json -Compress)"
    Check "build came back at index 2 with its name" ($build -and $build.Name -eq 'build') "windows=$($after | ConvertTo-Json -Compress)"
    $allPanes = ((& $PSMUX list-panes -s -t work -F '#{window_index}|#{pane_id}|#{pane_current_path}' 2>&1) -join ' ; ')
    Check "build has its split again (2 panes)" ($build -and $build.Panes -eq 2) "panes=$($build.Panes) all=[$allPanes] restore output: $out"
    Check "editor was not touched (same pane id)" ((Get-PaneIds 'work:0')[0] -eq $editorPaneBefore) "before=$editorPaneBefore after=$((Get-PaneIds 'work:0')[0])"
    Check "active window of the running session stayed on editor" (($after | Where-Object Active).Index -eq 0) "active=$(($after | Where-Object Active).Index)"
    Check "done is still one window" ((Get-Windows 'done').Count -eq 1) ''

    Check "report: work reported as kept with 2 windows added" ($out -match 'Kept running session: work \(2 missing windows added\)') "Output: $out"
    Check "report: done reported as complete and left alone" ($out -match 'Still running and complete, left alone: done') "Output: $out"
    Check "report: no session counted as restored from scratch" ($out -notmatch 'Restored session:') "Output: $out"
    Check "report: summary counts added windows and left-alone sessions" ($out -match 'restored 0/2, added 2 windows to 1 running, left 1 alone') "Output: $out"

    # --- second restore: nothing missing any more ---
    Write-Host "`n--- restore again, everything complete ---" -ForegroundColor Yellow
    $out2 = (& pwsh -NoProfile -File $RESTORE_SCRIPT 2>&1 | Out-String)
    Start-Sleep -Milliseconds 500
    Check "no windows added the second time" ((Get-Windows 'work').Count -eq 3) "windows=$((Get-Windows 'work') | ConvertTo-Json -Compress)"
    Check "report: both sessions left alone" ($out2 -match 'Still running and complete, left alone: .*work' -and $out2 -match 'nothing to restore, all 2 saved sessions are still running') "Output: $out2"
}
finally {
    & $PSMUX kill-server 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    $env:USERPROFILE = $savedUserProfile
    if ($null -ne $savedDataDir) { $env:PSMUX_DATA_DIR = $savedDataDir } else { Remove-Item Env:PSMUX_DATA_DIR -ErrorAction SilentlyContinue }
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Magenta
Write-Host "  resurrect reconcile" -ForegroundColor Magenta
Write-Host "  PASS: $pass  FAIL: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
Write-Host "======================================" -ForegroundColor Magenta
if ($fail -gt 0) { exit 1 }
exit 0
