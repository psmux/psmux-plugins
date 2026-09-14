#!/usr/bin/env pwsh
# =============================================================================
# psmux-continuum: auto-save loop lifetime (single loop, reaps with the last
# server, hands over to a new server's loop, honours the save interval)
# =============================================================================
# Runs against the real psmux binary in a private data root (PSMUX_DATA_DIR)
# with USERPROFILE redirected. Takes about two minutes because it has to wait
# for a real one minute save cadence and a real reap.
#
# Covers:
#   single loop     two loops started back to back (one per session server,
#                   the shape client-attached produces): exactly one survives
#   cadence         @continuum-save-interval 1 produces a save within 80 s
#                   even though the hook passes -IntervalMinutes 15
#   reap            after kill-server the loop exits within 30 s, not at the
#                   next save tick
#   restart         kill-server plus a new server inside the old loop's
#                   liveness window leaves exactly one loop (the old one
#                   carries on, or the newcomer takes the mutex), and that
#                   survivor still reaps on the final kill-server
# Run:  pwsh -File tests/test_continuum_lifetime.ps1
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "  FAIL: $name$(if($detail){' >> ' + $detail})" -ForegroundColor Red; $script:fail++ }
}

$PLUGIN_ROOT = Split-Path $PSScriptRoot -Parent
$AUTO_SAVE   = Join-Path $PLUGIN_ROOT 'psmux-continuum\scripts\auto_save.ps1'
$PSMUX = (Get-Command psmux -ErrorAction Stop).Source

Write-Host "`n=== psmux-continuum auto-save lifetime test (isolated server) ===" -ForegroundColor Magenta

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("psmux-lifetime-{0}" -f ([guid]::NewGuid().ToString('N')))
$sbHome  = Join-Path $sandbox 'home'
$data    = Join-Path $sandbox 'data'
New-Item -ItemType Directory -Path (Join-Path $sbHome '.psmux\resurrect'), $data -Force | Out-Null

$savedUserProfile = $env:USERPROFILE
$savedDataDir     = $env:PSMUX_DATA_DIR
$env:USERPROFILE    = $sbHome
$env:PSMUX_DATA_DIR = $data
foreach ($v in 'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE') {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}

$loops = @()
function Start-Loop {
    $p = Start-Process pwsh -ArgumentList @('-NoProfile', '-File', $AUTO_SAVE, '-IntervalMinutes', '15') -PassThru -WindowStyle Hidden
    $script:loops += $p
    return $p
}
function Count-Live($procs) { @($procs | Where-Object { -not $_.HasExited }).Count }
function Wait-Session([string]$name) {
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        & $PSMUX has-session -t $name 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

try {
    & $PSMUX new-session -d -s alpha 2>&1 | Out-Null
    Check "fixture: session alpha up" (Wait-Session 'alpha') ''
    & $PSMUX new-session -d -s beta 2>&1 | Out-Null
    Check "fixture: session beta up" (Wait-Session 'beta') ''
    & $PSMUX set-option -g '@continuum-save-interval' '1' 2>&1 | Out-Null

    # --- single loop: two starts, one survivor ---
    Write-Host "`n--- single loop ---" -ForegroundColor Yellow
    $a = Start-Loop
    Start-Sleep -Seconds 2
    $b = Start-Loop
    Start-Sleep -Seconds 25   # longer than the mutex handover wait
    Check "first loop is running" (-not $a.HasExited) ''
    Check "second loop gave up on the held mutex and exited" ($b.HasExited) "b exited=$($b.HasExited)"

    # --- cadence: option 1 minute beats the hook's 15 ---
    Write-Host "`n--- cadence ---" -ForegroundColor Yellow
    $deadline = (Get-Date).AddSeconds(60)
    $saves = @()
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $saves = @(Get-ChildItem (Join-Path $sbHome '.psmux\resurrect') -Filter 'psmux_resurrect_*.json' -ErrorAction SilentlyContinue)
        if ($saves.Count -gt 0) { break }
    }
    Check "a save appeared within ~85 s with @continuum-save-interval 1" ($saves.Count -ge 1) "saves=$($saves.Count)"
    if ($saves.Count -ge 1) {
        $names = @((Get-Content $saves[0].FullName -Raw | ConvertFrom-Json).sessions.name)
        Check "the save covers both sessions (one loop saves everything)" (($names -contains 'alpha') -and ($names -contains 'beta')) "names=[$($names -join ', ')]"
    }

    # --- reap: kill-server, loop exits within 30 s ---
    Write-Host "`n--- reap ---" -ForegroundColor Yellow
    & $PSMUX kill-server 2>&1 | Out-Null
    $gone = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ($a.HasExited) { $gone = $true; break }
    }
    Check "loop exited within 30 s of kill-server" $gone "exited=$($a.HasExited)"

    # --- restart inside the liveness window: still exactly one loop ---
    # The server is killed and a new one started before the old loop's next
    # liveness check. Either the old loop sees the new server and carries on
    # serving it (the newcomer then times out on the mutex), or the old loop
    # already noticed the gap and exited and the newcomer takes the mutex.
    # Both are fine; what must never happen is zero loops or two.
    Write-Host "`n--- restart inside the liveness window ---" -ForegroundColor Yellow
    & $PSMUX new-session -d -s gamma 2>&1 | Out-Null
    Check "fixture: session gamma up" (Wait-Session 'gamma') ''
    $c = Start-Loop
    Start-Sleep -Seconds 2
    & $PSMUX kill-server 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    & $PSMUX new-session -d -s delta 2>&1 | Out-Null
    Check "fixture: session delta up" (Wait-Session 'delta') ''
    $d = Start-Loop                                # starts while c still holds the mutex
    Start-Sleep -Seconds 25                        # longer than the mutex handover wait
    $live = Count-Live @($c, $d)
    Check "exactly one loop survives a restart inside the liveness window" ($live -eq 1) "c exited=$($c.HasExited) d exited=$($d.HasExited)"

    # --- and that survivor still reaps when the last server goes away ---
    & $PSMUX kill-server 2>&1 | Out-Null
    $gone = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ((Count-Live @($c, $d)) -eq 0) { $gone = $true; break }
    }
    Check "surviving loop exited within 30 s of the final kill-server" $gone "c exited=$($c.HasExited) d exited=$($d.HasExited)"
}
finally {
    & $PSMUX kill-server 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    foreach ($p in $loops) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
    $env:USERPROFILE = $savedUserProfile
    if ($null -ne $savedDataDir) { $env:PSMUX_DATA_DIR = $savedDataDir } else { Remove-Item Env:PSMUX_DATA_DIR -ErrorAction SilentlyContinue }
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Magenta
Write-Host "  continuum auto-save lifetime" -ForegroundColor Magenta
Write-Host "  PASS: $pass  FAIL: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
Write-Host "======================================" -ForegroundColor Magenta
if ($fail -gt 0) { exit 1 }
exit 0
