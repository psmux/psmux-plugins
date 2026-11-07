#!/usr/bin/env pwsh
# Real psmux integration test. Run only in a disposable Windows VM:
#   $env:PSMUX_DISPOSABLE_TEST = '1'
#   pwsh -NoProfile -File tests/test_resurrect_startup.ps1
param([string]$ArtifactsDir = '')
$ErrorActionPreference = 'Stop'
if ($env:PSMUX_DISPOSABLE_TEST -ne '1') { throw 'Disposable VM required (PSMUX_DISPOSABLE_TEST=1).' }

$real = (Get-Command psmux -ErrorAction Stop).Source
$repo = Split-Path $PSScriptRoot -Parent
$root = Join-Path ([IO.Path]::GetTempPath()) ('psmux-startup-' + [guid]::NewGuid().ToString('N'))
$profile = Join-Path $root 'home'
$data = Join-Path $root 'data'
$plugins = Join-Path $root 'plugins'
$markers = Join-Path $root 'markers'
$driverNamespace = 'startup_driver_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$driverConfig = Join-Path $root 'driver.conf'
$restore = Join-Path $plugins 'psmux-resurrect/scripts/restore.ps1'
$autoRestore = Join-Path $plugins 'psmux-continuum/scripts/auto_restore.ps1'
$pass = 0; $fail = 0
$environment = @{}
foreach ($key in 'USERPROFILE','PSMUX_DATA_DIR','PATH','PATHEXT','PSMUX_ALLOW_NESTING','PSMUX_SESSION','PSMUX_ACTIVE','PSMUX_SESSION_NAME','PSMUX_TARGET_SESSION','PSMUX_ROUTE_WARM','TMUX','TMUX_PANE') {
    $environment[$key] = [Environment]::GetEnvironmentVariable($key)
}

function Check($name, $condition, $detail = '') {
    if ($condition) { $script:pass++; Write-Host "  PASS: $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL: $name $detail" -ForegroundColor Red }
}
function Require($name, $condition) {
    if (-not $condition) { throw "Precondition failed: $name" }
}
function Native([string[]]$Arguments, [switch]$AllowFailure, [switch]$Driver) {
    $ns = if ($Driver) { $driverNamespace } else { $namespace }
    $cfg = if ($Driver) { $driverConfig } else { $config }
    $si = [Diagnostics.ProcessStartInfo]::new()
    $si.FileName = $real
    foreach ($a in (@('-L', $ns, '-f', $cfg) + $Arguments)) { $si.ArgumentList.Add($a) }
    $si.UseShellExecute = $false; $si.RedirectStandardOutput = $true; $si.RedirectStandardError = $true
    $p = [Diagnostics.Process]::new(); $p.StartInfo = $si
    try {
        [void]$p.Start()
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(20000)) { $p.Kill($true); throw "Native timeout: $Arguments" }
        $text = $o.GetAwaiter().GetResult().TrimEnd([char[]]"`r`n")
        $errorText = $e.GetAwaiter().GetResult()
        if ($p.ExitCode -ne 0 -and -not $AllowFailure) { throw "Native failure: $Arguments : $text $errorText" }
        [pscustomobject]@{ Code = $p.ExitCode; Text = $text; Error = $errorText }
    } finally { $p.Dispose() }
}
function Run-Script([string]$Path, [string[]]$Arguments = @()) {
    $beforeHash = if ($snapshot -and $Path -in @($restore, $autoRestore)) { (Get-FileHash $snapshot).Hash }
    $si = [Diagnostics.ProcessStartInfo]::new(); $si.FileName = (Get-Command pwsh).Source
    foreach ($a in (@('-NoProfile', '-File', $Path) + $Arguments)) { $si.ArgumentList.Add($a) }
    $si.UseShellExecute = $false; $si.RedirectStandardOutput = $true; $si.RedirectStandardError = $true
    $p = [Diagnostics.Process]::new(); $p.StartInfo = $si
    try {
        [void]$p.Start()
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(120000)) { $p.Kill($true); throw "Script timeout: $Path" }
        $text = $o.GetAwaiter().GetResult(); $errorText = $e.GetAwaiter().GetResult()
        if ($ArtifactsDir) {
            $script:run++
            @{ Path = $Path; Arguments = $Arguments; Exit = $p.ExitCode; Stdout = $text; Stderr = $errorText } | ConvertTo-Json | Set-Content (Join-Path $ArtifactsDir "run-$run.json")
        }
        if ($p.ExitCode -ne 0) { throw "Script failure: $Path : $text $errorText" }
        Require 'test restore was not skipped by a concurrent restore' ($text -notmatch 'another restore is in progress')
        if ($beforeHash) { Require 'restore leaves snapshot bytes unchanged' ((Get-FileHash $snapshot).Hash -eq $beforeHash) }
        $text
    } finally { $p.Dispose() }
}
function Configure([bool]$Automatic) {
    @"
set -g default-shell pwsh
set -g default-command 'pwsh -NoLogo -NoProfile'
set -g @continuum-save-interval '0'
set -g @continuum-restore '$(if ($Automatic) { 'on' } else { 'off' })'
set -g @resurrect-overwrite 'off'
set -g @resurrect-processes '~Add-Content'
set-hook -g session-created 'run-shell "pwsh -NoProfile -File $hook"'
"@ | Set-Content $config
}
function Reset([bool]$Automatic = $false) {
    Native @('kill-server') -AllowFailure -Driver | Out-Null
    Native @('kill-server') -AllowFailure | Out-Null
    $remaining = Native @('list-sessions', '-F', '#{session_name}') -AllowFailure
    Require 'namespace empty after reset' (-not $remaining.Text -or $remaining.Code -ne 0)
    Get-ChildItem $markers -File | Remove-Item
    Bind-Tools
    Configure $Automatic
}
function Pane([string]$Target, [string]$Format = '#{pane_pid}', [switch]$AllowFailure) {
    (Native @('display-message', '-p', '-t', $Target, $Format) -AllowFailure:$AllowFailure).Text
}
function Launches {
    $lines = @(Get-ChildItem $markers -Filter '*.txt' | ForEach-Object { Get-Content $_.FullName })
    $lines.Count
}
function Wait-Restore {
    $done = Join-Path $root "auto-${namespace}__main.exit"
    $deadline = (Get-Date).AddSeconds(40)
    while (-not (Test-Path $done) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
    Require 'automatic restore completes' (Test-Path $done)
    Require 'automatic restore exits successfully' ((Get-Content $done -Raw).Trim() -eq '0')
    if ($ArtifactsDir) { Copy-Item (Join-Path $root "auto-${namespace}__*") $ArtifactsDir }
}
function Record([string]$Name) {
    if (-not $ArtifactsDir) { return }
    @{
        Panes = Native @('list-panes', '-a', '-F', '#{session_name}|#{window_index}|#{pane_index}|#{pane_id}|#{pane_pid}|#{pane_current_path}|#{pane_active}') -AllowFailure
        Markers = @(Get-ChildItem $markers -File | ForEach-Object { @{ Name = $_.Name; Lines = @(Get-Content $_.FullName) } })
        Windows = Native @('list-windows', '-t', 'main', '-F', '#{window_index}|#{window_name}|#{window_active}|#{window_zoomed_flag}') -AllowFailure
    } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $ArtifactsDir "$Name.json")
}

function Bind-Tools {
    # A fresh namespace per case avoids inheriting options from warm servers.
    $script:namespace = 'startup_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $script:bin = Join-Path $root $namespace
    $script:config = Join-Path $profile "$namespace.conf"
    $script:hook = Join-Path $root "$namespace-hook.ps1"
    New-Item -ItemType Directory $bin -Force | Out-Null
    # The PATH shim routes unmodified plugin scripts into this test's namespace.
    @"
`$si = [Diagnostics.ProcessStartInfo]::new(); `$si.FileName = '$real'
if (`$args[0] -eq 'list-panes' -and `$args -contains '#{window_index}|#{pane_index}' -and (Test-Path '$root/pane-query-reply.txt')) {
    `$reply = (Get-Content '$root/pane-query-reply.txt' -Raw).Trim()
    Set-Content '$root/pane-query-used.txt' `$reply
    switch (`$reply) { 'failed' { exit 1 }; 'empty' { exit 0 }; 'malformed' { '0|0|extra'; exit 0 } }
}
foreach (`$a in (@('-L','$namespace','-f','$config') + `$args)) { `$si.ArgumentList.Add(`$a) }
`$si.UseShellExecute = `$false; `$si.RedirectStandardOutput = `$true; `$si.RedirectStandardError = `$true
`$p = [Diagnostics.Process]::new(); `$p.StartInfo = `$si
try {
    [void]`$p.Start(); `$o = `$p.StandardOutput.ReadToEndAsync(); `$e = `$p.StandardError.ReadToEndAsync()
    if (-not `$p.WaitForExit(20000)) { `$p.Kill(`$true); throw 'Wrapper timeout' }
    `$text = `$o.GetAwaiter().GetResult()
    if (`$args[0] -eq 'list-panes' -and (`$args -join ' ').Contains('#{q:')) {
        [Console]::Write(`$text)
    } elseif (`$text) { `$text.TrimEnd([char[]]"``r``n") -split "``r?``n" }
    [Console]::Error.Write(`$e.GetAwaiter().GetResult()); exit `$p.ExitCode
} finally { `$p.Dispose() }
"@ | Set-Content (Join-Path $bin 'psmux.ps1')
    $env:PATH = "$bin;$($environment['PATH'])"; $env:PATHEXT = ".PS1;$($environment['PATHEXT'])"
    # Hooks launch their own shell. Bind its CLI edge to the same private shim.
    @"
`$env:PATH = '$bin;' + `$env:PATH
`$env:PATHEXT = '.PS1;' + `$env:PATHEXT
& pwsh -NoProfile -File '$autoRestore' > ('$root/auto-' + `$env:PSMUX_TARGET_SESSION + '.stdout.txt') 2> ('$root/auto-' + `$env:PSMUX_TARGET_SESSION + '.stderr.txt')
Set-Content ('$root/auto-' + `$env:PSMUX_TARGET_SESSION + '.exit') `$LASTEXITCODE
"@ | Set-Content $hook
}

try {
    New-Item -ItemType Directory $profile,$data,$plugins,$markers -Force | Out-Null
    if ($ArtifactsDir) { New-Item -ItemType Directory $ArtifactsDir -Force | Out-Null }
    foreach ($name in 'psmux-resurrect','psmux-continuum') { Copy-Item (Join-Path $repo $name) $plugins -Recurse }
    $env:USERPROFILE = $profile; $env:PSMUX_DATA_DIR = $data; $env:PSMUX_ALLOW_NESTING = '1'
    foreach ($key in 'PSMUX_SESSION','PSMUX_ACTIVE','PSMUX_SESSION_NAME','PSMUX_TARGET_SESSION','PSMUX_ROUTE_WARM','TMUX','TMUX_PANE') {
        Remove-Item "Env:$key" -ErrorAction SilentlyContinue
    }
    Bind-Tools
    'set -g default-shell pwsh' | Set-Content $driverConfig
    Configure $false

    Native @('new-session', '-d', '-s', 'aux') | Out-Null
    Native @('new-session', '-d', '-s', 'main', '-n', 'saved-zero', '-c', $profile) | Out-Null
    Native @('split-window', '-h', '-t', 'main:0', '-c', $profile) | Out-Null
    Native @('new-window', '-t', 'main', '-n', 'saved-one', '-c', $profile) | Out-Null
    Native @('split-window', '-t', 'main:1', '-c', $profile) | Out-Null
    Native @('select-pane', '-t', 'main:0.1') | Out-Null
    Native @('select-pane', '-t', 'main:1.1') | Out-Null
    Native @('select-window', '-t', 'main:1') | Out-Null
    Run-Script (Join-Path $plugins 'psmux-resurrect/scripts/save.ps1') | Out-Null
    $last = Join-Path $profile '.psmux/resurrect/last'
    Require 'fixture snapshot exists' (Test-Path $last)
    $snapshot = (Get-Content $last -Raw).Trim()
    $fixture = Get-Content $snapshot -Raw | ConvertFrom-Json
    Require 'fixture has two sessions, main has two split windows' (@($fixture.sessions).Count -eq 2 -and @($fixture.sessions | Where-Object name -eq main).windows.Count -eq 2 -and @($fixture.sessions | Where-Object name -eq main).windows[0].panes.Count -eq 2)
    $savedDir = Join-Path $profile 'saved-work'
    New-Item -ItemType Directory $savedDir -Force | Out-Null
    foreach ($session in $fixture.sessions) { foreach ($win in $session.windows) { foreach ($pane in $win.panes) {
        $label = "$($session.name)-w$($win.index)p$($pane.index)"
        $pane.directory = $savedDir
        $pane.command = "Add-Content -LiteralPath '$markers/$label.txt' -Value (`"`$PID|`$(`$PWD.Path)`")"
    } } }
    ($fixture.sessions | Where-Object name -eq main).windows[0].zoomed = $true
    $fixture | ConvertTo-Json -Depth 15 | Set-Content $snapshot
    $snapshotText = Get-Content $snapshot -Raw
    $snapshotHash = (Get-FileHash $snapshot).Hash

    # Exercise the generated auto_restore.ps1 as well as the checked-in copy.
    Run-Script (Join-Path $plugins 'psmux-continuum/psmux-continuum.ps1') | Out-Null
    Require 'generator and checked-in auto-restore scripts agree' ((Get-Content $autoRestore -Raw).Trim() -eq (Get-Content (Join-Path $repo 'psmux-continuum/scripts/auto_restore.ps1') -Raw).Trim())

    Reset $true
    # A real attached client runs inside another private psmux pane, providing
    # the terminal that a WT profile normally supplies. It uses the WT command.
    $clientScript = Join-Path $root 'client.ps1'
    @"
foreach (`$key in 'PSMUX_SESSION','PSMUX_ACTIVE','PSMUX_SESSION_NAME','PSMUX_TARGET_SESSION','PSMUX_ROUTE_WARM','TMUX','TMUX_PANE') {
    Remove-Item "Env:`$key" -ErrorAction SilentlyContinue
}
& '$real' -L '$namespace' -f '$config' new-session -A -s main
"@ | Set-Content $clientScript
    Native @('new-session', '-d', '-s', 'driver', "pwsh -NoProfile -File $clientScript") -Driver | Out-Null
    Wait-Restore
    Record 'attached-automatic'
    Check 'attached new-session -A restores all five commands once' ((Launches) -eq 5)
    Check 'startup window gets its saved name' ((Pane 'main:0.0' '#{window_name}') -eq 'saved-zero')
    Check 'startup pane gets its saved working directory' ((Pane 'main:0.0' '#{pane_current_path}') -eq $savedDir)
    Check 'first window saved zoom state restored' ((Pane 'main:0.0' '#{window_zoomed_flag}') -eq '1')
    Check 'saved active window selected' ((Native @('list-windows', '-t', 'main', '-F', '#{window_index}|#{window_active}')).Text -match '(?m)^1\|1$')
    Check 'saved active pane in first window selected' ((Pane 'main:0.1' '#{pane_active}' -AllowFailure) -eq '1')
    Check 'saved active pane in active window selected' ((Pane 'main:1.1' '#{pane_active}' -AllowFailure) -eq '1')
    $firstMarker = Join-Path $markers 'main-w0p0.txt'
    Check 'first command ran in the intended main pane' ((Test-Path $firstMarker) -and (Get-Content $firstMarker -Raw).StartsWith((Pane 'main:0.0') + '|'))
    $startupOutput = Get-Content (Join-Path $root "auto-${namespace}__main.stdout.txt") -Raw
    Check 'startup session counted as restored with both windows' ($startupOutput -match 'Restored startup session: main \(2 windows\)' -and $startupOutput -match 'restored 2 sessions, 3 windows')
    Native @('resize-pane', '-Z', '-t', 'main:0.1') | Out-Null
    Check 'first window restores the saved horizontal split' ((Pane 'main:0.0' '#{pane_top}') -eq (Pane 'main:0.1' '#{pane_top}' -AllowFailure) -and (Pane 'main:0.0' '#{pane_left}') -ne (Pane 'main:0.1' '#{pane_left}' -AllowFailure))
    Check 'automatic restore leaves snapshot bytes unchanged' ((Get-FileHash $snapshot).Hash -eq $snapshotHash)
    Run-Script $restore | Out-Null
    Check 'manual restore after startup does not replay commands' ((Launches) -eq 5)

    Reset
    Native @('new-session', '-d', '-s', 'main') | Out-Null
    $before = Pane 'main:0.0'
    Run-Script $restore | Out-Null
    Record 'manual'
    Check 'manual restore preserves initial pane process' ((Pane 'main:0.0') -eq $before)
    Check 'manual restore only launches other three commands' ((Launches) -eq 3 -and -not (Test-Path $firstMarker))

    Reset
    Native @('new-session', '-d', '-s', 'main') | Out-Null
    $before = Pane 'main:0.0'
    $ready = Join-Path $root 'busy-ready.txt'
    Native @('send-keys', '-t', 'main:0.0', "Set-Content '$ready' `$PID; Start-Sleep -Seconds 600", 'Enter') | Out-Null
    $deadline = (Get-Date).AddSeconds(10)
    while (-not (Test-Path $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
    Require 'manual restore fixture has a working command' ((Test-Path $ready) -and (Get-Content $ready -Raw).Trim() -eq $before)
    Run-Script $restore | Out-Null
    Check 'manual restore preserves a working sole pane' ((Pane 'main:0.0') -eq $before -and [bool](Get-Process -Id ([int]$before) -ErrorAction SilentlyContinue) -and -not (Test-Path $firstMarker))

    Reset
    Native @('new-session', '-d', '-s', 'main') | Out-Null
    $before = Pane 'main:0.0'
    Wait-Restore
    Run-Script $autoRestore | Out-Null
    Check 'automatic restore disabled leaves even missing windows alone' ((Pane 'main:0.0') -eq $before -and (Launches) -eq 0 -and (Native @('list-windows', '-t', 'main', '-F', '#{window_index}')).Text -eq '0')
    Native @('set-option', '-g', '@continuum-restore', 'on') | Out-Null
    Run-Script $autoRestore | Out-Null
    Check 'automatic caller without startup context stays conservative' ((Pane 'main:0.0') -eq $before -and (Launches) -eq 3 -and -not (Test-Path $firstMarker))

    Reset
    Native @('new-session', '-d', '-s', 'aux') | Out-Null
    Native @('new-session', '-d', '-s', 'main') | Out-Null
    $auxBefore = Pane 'aux:0.0'
    Run-Script $restore @('-InitialSession', "${namespace}__main") | Out-Null
    Record 'existing-other-session'
    Check 'startup restores all four main commands beside an existing session' ((Launches) -eq 4 -and (Test-Path $firstMarker))
    Check 'existing other session keeps its process and runs no saved command' ((Pane 'aux:0.0') -eq $auxBefore -and -not (Test-Path (Join-Path $markers 'aux-w0p0.txt')))

    foreach ($shape in 'split','two-windows') {
        Reset
        Native @('new-session', '-d', '-s', 'main') | Out-Null
        if ($shape -eq 'split') { Native @('split-window', '-t', 'main:0') | Out-Null }
        else { Native @('new-window', '-t', 'main') | Out-Null }
        $before = Pane 'main:0.0'
        Run-Script $restore @('-InitialSession', "${namespace}__main") | Out-Null
        Record $shape
        Check "$shape session is preserved even with startup context" ((Pane 'main:0.0') -eq $before -and -not (Test-Path $firstMarker))
    }

    foreach ($reply in 'failed','empty','malformed') {
        Reset
        Native @('new-session', '-d', '-s', 'main') | Out-Null
        $before = Pane 'main:0.0'
        $reply | Set-Content (Join-Path $root 'pane-query-reply.txt')
        Run-Script $restore @('-InitialSession', "${namespace}__main") | Out-Null
        Require "$reply query response was exercised" ((Test-Path (Join-Path $root 'pane-query-used.txt')) -and (Get-Content (Join-Path $root 'pane-query-used.txt') -Raw).Trim() -eq $reply)
        Check "$reply pane query cannot authorize replacement" ((Pane 'main:0.0') -eq $before -and -not (Test-Path $firstMarker))
        Remove-Item (Join-Path $root 'pane-query-reply.txt'),(Join-Path $root 'pane-query-used.txt')
    }

    Reset
    Native @('new-session', '-d', '-s', 'main') | Out-Null
    $before = Pane 'main:0.0'
    Run-Script $restore @('-InitialSession', "${namespace}__missing") | Out-Null
    Check 'missing startup target cannot authorize replacement of main' ((Pane 'main:0.0') -eq $before -and -not (Test-Path $firstMarker))

    Reset
    Native @('new-session', '-d', '-s', 'main') | Out-Null
    $before = Pane 'main:0.0'
    $changed = $snapshotText | ConvertFrom-Json
    ($changed.sessions | Where-Object name -eq main).windows[0].index = 3
    $changed | ConvertTo-Json -Depth 15 | Set-Content $snapshot
    Run-Script $restore @('-InitialSession', "${namespace}__main") | Out-Null
    Record 'no-matching-saved-window'
    Check 'startup window absent from save is preserved' ((Pane 'main:0.0') -eq $before)
    $snapshotText | Set-Content $snapshot -NoNewline

}
finally {
    if ($config -and (Test-Path $config)) { Native @('kill-server') -AllowFailure -Driver | Out-Null; Native @('kill-server') -AllowFailure | Out-Null }
    foreach ($key in $environment.Keys) { [Environment]::SetEnvironmentVariable($key, $environment[$key]) }
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "`n=== Startup restore: $pass passed, $fail failed ==="
if ($fail) { exit 1 }
