#!/usr/bin/env pwsh
# Hermetic capture/retry tests. Every psmux invocation resolves to the fixture.
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check($name, $condition, $detail = '') {
    if ($condition) { Write-Host "  PASS: $name"; $script:pass++ }
    else { Write-Host "  FAIL: $name >> $detail"; $script:fail++ }
}
$save = Join-Path (Split-Path $PSScriptRoot -Parent) 'psmux-resurrect\scripts\save.ps1'
$root = Join-Path $env:TEMP ('capture-test-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $root 'bin'
$homeDir = Join-Path $root 'home'
$dir = Join-Path $homeDir '.psmux\resurrect'
New-Item -ItemType Directory $bin, $dir -Force | Out-Null
@'
$sub = $args[0]
$mode = $env:CAPTURE_MODE
$state = Join-Path $env:CAPTURE_ROOT 'attempt'
$attempt = if (Test-Path $state) { [int](Get-Content $state) } else { 0 }
function Row($wi, $name, $wa, $pi, $pa, $command) {
    $title = switch ($mode) {
        'tabs' { "build`t123" }
        'newlines' { "build`n123`npath\quote" }
        default { 'title|with pipe' }
    }
    (@($wi, $name, $wa, 'layout', '0', '*', $pi, 'C:\work space', $pa, $title, '4321', $command) | ForEach-Object {
        ([string]$_).Replace('\', '\\').Replace("`t", "\`t").Replace("`n", "\`n")
    }) -join "`t"
}
if ($sub -eq 'show-options') {
    if ($args -contains '@resurrect-save-command-strategy') { $env:CAPTURE_STRATEGY }
    if ($args -contains '@resurrect-save-unnamed') {
        if ($mode -eq 'filtered') { 'off' } else { 'auto' }
    }
    exit 0
}
if ($sub -eq 'list-sessions') {
    $attempt++; Set-Content $state $attempt
    "sessions:$attempt" | Add-Content (Join-Path $env:CAPTURE_ROOT 'queries')
    if ($mode -eq 'sessions-fail' -or ($mode -eq 'sessions-recover' -and $attempt -lt 3)) { 'connection failed'; exit 1 }
    if ($mode -eq 'none') { exit 0 }
    if ($mode -in 'policy','filtered') { '0'; '1'; '__internal' } else { 'alpha'; 'beta' }
    exit 0
}
if ($sub -eq 'list-windows') { throw 'Nested window queries must not be used.' }
if ($sub -eq 'list-panes') {
    "panes:${attempt}:$($args[3])" | Add-Content (Join-Path $env:CAPTURE_ROOT 'queries')
    if ($mode -eq 'panes-fail' -and $args -contains 'beta') { '0|looks|valid|but|failed'; exit 1 }
    if ($mode -eq 'transient' -and $attempt -eq 1 -and $args -contains 'beta') { 'connection failed'; exit 1 }
    if ($mode -eq 'empty' -and $args -contains 'beta') { exit 0 }
    if ($mode -eq 'malformed' -and $args -contains 'beta') { 'psmux: bad response'; exit 0 }
    if ($mode -eq 'bad-index' -and $args -contains 'beta') { Row 'nope' 'broken' 1 0 1 'pwsh'; exit 0 }
    if ($mode -eq 'policy') {
        [Console]::Write((Row 0 'main' 1 0 1 'pwsh') + "`n")
        if ($args -contains '1') { [Console]::Write((Row 0 'main' 1 1 0 'pwsh') + "`n") }
        exit 0
    }
    if ($mode -eq 'dangling') {
        [Console]::Write((Row 3 'window' 1 2 1 'clod') + '\')
        exit 0
    }
    if ($mode -eq 'carriage') {
        [Console]::Write((Row 3 'window' 1 2 1 "clod`r") + "`n")
        exit 0
    }
    [Console]::Write((Row 3 'window|name' 1 2 1 "pwsh | Write-Output 'literal'") + "`n")
    [Console]::Write((Row 3 'window|name' 1 3 0 'nvim') + "`n")
    [Console]::Write((Row 7 'other' 0 2 1 'pwsh') + "`n")
    exit 0
}
if ($sub -eq 'capture-pane') { 'contents'; exit 0 }
exit 0
'@ | Set-Content "$bin\psmux.ps1"
$vars = @('USERPROFILE','PATH','PATHEXT','CAPTURE_ROOT','CAPTURE_MODE','CAPTURE_STRATEGY')
$old = @{}
foreach ($v in $vars) { $old[$v] = [Environment]::GetEnvironmentVariable($v,'Process') }
function Run([string]$mode, [string]$strategyBody = '') {
    $env:CAPTURE_STRATEGY = if ($strategyBody) { 'record' } else { '' }
    $strategies = Join-Path $homeDir '.psmux\strategies\save_command_strategies'
    New-Item -ItemType Directory $strategies -Force | Out-Null
    $strategyBody | Set-Content (Join-Path $strategies 'record.ps1')
    Remove-Item "$root\strategy-calls" -ErrorAction SilentlyContinue
    Get-ChildItem $dir -File | Remove-Item -Force
    Remove-Item "$root\attempt", "$root\queries", "$root\delays" -ErrorAction SilentlyContinue
    $good = Join-Path $dir 'psmux_resurrect_20260101_120000.json'
    '{"version":2,"sessions":[{"name":"good","windows":[]}]}' | Set-Content $good
    $good | Set-Content "$dir\last"
    $before = (Get-FileHash "$dir\last").Hash
    $env:CAPTURE_MODE = $mode
    # Replace only the waiting clock; query and persistence behavior stays real.
    $invocation = @"
function Start-Sleep { param([int]`$Seconds, [int]`$Milliseconds); "`$Seconds|`$Milliseconds" | Add-Content '`$env:CAPTURE_ROOT\delays' }
& '$($save.Replace("'","''"))'
"@
    # Expand CAPTURE_ROOT in the fixture's clock path, without expanding its parameters.
    $invocation = $invocation.Replace("'`$env:CAPTURE_ROOT\delays'", "'$root\delays'")
    $output = & pwsh -NoProfile -Command $invocation 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $path = (Get-Content "$dir\last" -Raw).Trim()
    [pscustomobject]@{
        Exit = $exit; Output = $output; Snapshot = (Get-Content $path -Raw | ConvertFrom-Json)
        LastUnchanged = ((Get-FileHash "$dir\last").Hash -eq $before)
        GoodUnchanged = ((Get-Content $good -Raw).Trim() -eq '{"version":2,"sessions":[{"name":"good","windows":[]}]}')
        Count = @(Get-ChildItem $dir -Filter *.json).Count
        Attempts = [int](Get-Content "$root\attempt")
        Delays = @(Get-Content "$root\delays" -ErrorAction SilentlyContinue)
        Queries = @(Get-Content "$root\queries" -ErrorAction SilentlyContinue)
        StrategyCalls = @(Get-Content "$root\strategy-calls" -ErrorAction SilentlyContinue)
    }
}
try {
    $env:USERPROFILE = $homeDir; $env:PATH = "$bin;$env:PATH"; $env:PATHEXT = ".PS1;$env:PATHEXT"
    $env:CAPTURE_ROOT = $root
    $r = Run 'full'
    Check 'complete capture succeeds without retries' ($r.Exit -eq 0 -and $r.Attempts -eq 1 -and $r.Delays.Count -eq 0) $r.Output
    Check 'complete capture promotes a new snapshot' (-not $r.LastUnchanged -and $r.Count -eq 2)
    Check 'single query groups three panes into two windows per session' ($r.Snapshot.sessions.Count -eq 2 -and $r.Snapshot.sessions[0].windows.Count -eq 2 -and $r.Snapshot.sessions[0].windows[0].panes.Count -eq 2)
    Check 'commands, titles and window names containing pipes survive' ($r.Snapshot.sessions[0].windows[0].name -ceq 'window|name' -and $r.Snapshot.sessions[0].windows[0].panes[0].title -ceq 'title|with pipe' -and $r.Snapshot.sessions[0].windows[0].panes[0].command -ceq "pwsh | Write-Output 'literal'")
    Check 'PID is not persisted and format stays version 2' ($r.Snapshot.version -eq 2 -and $r.Snapshot.sessions[0].windows[0].panes[0].PSObject.Properties.Name -notcontains 'pid')
    $r = Run 'tabs'
    Check 'numeric title suffix following a tab cannot shift PID into command' ($r.Exit -eq 0 -and $r.Snapshot.sessions[0].windows[0].panes[0].title -ceq "build`t123" -and $r.Snapshot.sessions[0].windows[0].panes[0].command -ceq "pwsh | Write-Output 'literal'")
    $r = Run 'newlines'
    Check 'quoted newlines and backslashes preserve pane title and directory' ($r.Exit -eq 0 -and $r.Snapshot.sessions[0].windows[0].panes[0].title -ceq "build`n123`npath\quote" -and $r.Snapshot.sessions[0].windows[0].panes[0].directory -ceq 'C:\work space')
    $r = Run 'transient'
    Check 'transient pane-query failure retries and succeeds' ($r.Exit -eq 0 -and $r.Attempts -eq 2 -and -not $r.LastUnchanged) $r.Output
    Check 'retry starts again at session enumeration with 2-second backoff' (($r.Delays -join ',') -eq '2|0' -and @($r.Queries | Where-Object { $_ -like 'panes:*:alpha' }).Count -eq 2)
    Check 'retry discards all previously captured session data' ($r.Snapshot.sessions.Count -eq 2 -and @($r.Snapshot.sessions | Where-Object name -eq alpha).Count -eq 1)
    $r = Run 'sessions-recover'
    Check 'session enumeration can recover on third attempt' ($r.Exit -eq 0 -and $r.Attempts -eq 3 -and ($r.Delays -join ',') -eq '2|0,4|0') $r.Output
    foreach ($mode in 'sessions-fail','panes-fail','empty','malformed','bad-index','dangling','carriage') {
        $r = Run $mode
        Check "$mode returns failure after four attempts" ($r.Exit -ne 0 -and $r.Attempts -eq 4) $r.Output
        Check "$mode preserves last and previous snapshot without rotation" ($r.LastUnchanged -and $r.GoodUnchanged -and $r.Count -eq 1)
        Check "$mode waits 2, 4 and 6 seconds" (($r.Delays -join ',') -eq '2|0,4|0,6|0')
    }
    $r = Run 'policy'
    Check 'unnamed filtering still uses live commands and pane shape' ($r.Exit -eq 0 -and $r.Snapshot.sessions.Count -eq 1 -and $r.Snapshot.sessions[0].name -eq '1') $r.Output
    $r = Run 'filtered'
    Check 'all intentionally filtered sessions skip successfully without retry' ($r.Exit -eq 0 -and $r.Attempts -eq 1 -and $r.LastUnchanged -and $r.Delays.Count -eq 0) $r.Output
    $r = Run 'none'
    Check 'empty session enumeration never promotes an empty snapshot' ($r.LastUnchanged -and $r.Count -eq 1)
    $strategy = @'
param([string]$Command, [string]$PanePid, [string]$Directory)
Get-Content (Join-Path $env:CAPTURE_ROOT 'attempt') | Add-Content (Join-Path $env:CAPTURE_ROOT 'strategy-calls')
$Command
'@
    $r = Run 'transient' $strategy
    Check 'strategies run once per included pane only after successful retry' ($r.Exit -eq 0 -and $r.StrategyCalls.Count -eq 6 -and @($r.StrategyCalls | Where-Object { $_ -ne '2' }).Count -eq 0)
    $r = Run 'panes-fail' $strategy
    Check 'exhausted structural retries invoke no strategies' ($r.Exit -ne 0 -and $r.StrategyCalls.Count -eq 0)
    $r = Run 'full' ($strategy + "`nWrite-Output WRONG; exit 7")
    Check 'strategy failures preserve captured command without retrying capture' ($r.Exit -eq 0 -and $r.Attempts -eq 1 -and $r.Delays.Count -eq 0 -and $r.Snapshot.sessions[0].windows[0].panes[0].command -ceq "pwsh | Write-Output 'literal'")
} finally {
    foreach ($v in $vars) { [Environment]::SetEnvironmentVariable($v,$old[$v],'Process') }
    Remove-Item $root -Recurse -Force
}
Write-Host "Results: $pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
