#!/usr/bin/env pwsh
# Live save -> kill -> restore test. Uses a private data root and a unique -L
# namespace, a custom config, and an isolated user profile. Cleanup targets
# only that namespace. Run in a disposable Windows environment.
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL: $name >> $detail" -ForegroundColor Red; $script:fail++ }
}
function Wait-Until([scriptblock]$condition) {
    $deadline = (Get-Date).AddSeconds(30)
    do {
        if (& $condition) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}
$plugin = Join-Path (Split-Path $PSScriptRoot -Parent) 'psmux-resurrect'
$realPsmux = (Get-Command psmux -ErrorAction Stop).Source
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('save-e2e-' + [guid]::NewGuid().ToString('N'))
$homeDir = Join-Path $sandbox 'home'
$bin = Join-Path $sandbox 'bin'
$data = Join-Path $sandbox 'data'
$strategies = Join-Path $homeDir '.psmux\strategies\save_command_strategies'
New-Item -ItemType Directory -Path $homeDir, $bin, $data, $strategies -Force | Out-Null
$namespace = 'save_strategy_' + [guid]::NewGuid().ToString('N')
$config = Join-Path $sandbox 'psmux.conf'
@'
set -g default-shell pwsh
set -g default-command 'pwsh -NoLogo -NoProfile'
set -g @resurrect-save-command-strategy 'resume'
set -g @resurrect-processes '~Set-Content'
'@ | Set-Content $config
$wrapper = Join-Path $bin 'psmux.ps1'
@"
`$info = [Diagnostics.ProcessStartInfo]::new()
`$info.FileName = '$($realPsmux.Replace("'", "''"))'
foreach (`$argument in (@('-L', '$namespace', '-f', '$($config.Replace("'", "''"))') + `$args)) { `$info.ArgumentList.Add(`$argument) }
`$info.UseShellExecute = `$false
`$info.RedirectStandardOutput = `$true
`$info.RedirectStandardError = `$true
`$info.StandardOutputEncoding = [Text.UTF8Encoding]::new(`$false)
`$process = [Diagnostics.Process]::new()
`$process.StartInfo = `$info
try {
    [void]`$process.Start()
    `$stdout = `$process.StandardOutput.ReadToEndAsync()
    `$stderr = `$process.StandardError.ReadToEndAsync()
    `$process.WaitForExit()
    `$text = `$stdout.GetAwaiter().GetResult()
    if (`$args[0] -eq 'list-panes' -and `$args -contains '-s') { [Console]::Write(`$text) }
    elseif (`$text) { `$text.TrimEnd([char[]]"``r``n") -split "``r?``n" }
    [Console]::Error.Write(`$stderr.GetAwaiter().GetResult())
    `$code = `$process.ExitCode
} finally { `$process.Dispose() }
exit `$code
"@ | Set-Content $wrapper
@'
param([string]$Command, [string]$PanePid, [string]$Directory)
$path = (Join-Path $Directory "restored-$PanePid.txt").Replace("'", "''")
$value = "$Command|$PanePid".Replace("'", "''")
"Set-Content -LiteralPath '$path' -Value '$value'"
'@ | Set-Content (Join-Path $strategies 'resume.ps1')

$vars = @('USERPROFILE', 'PATH', 'PATHEXT', 'PSMUX_DATA_DIR', 'PSMUX_ALLOW_NESTING',
    'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE')
$old = @{}
foreach ($v in $vars) { $old[$v] = [Environment]::GetEnvironmentVariable($v, 'Process') }
function Invoke-Psmux {
    $out = & $wrapper @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "psmux $args failed: $out" }
    $out
}
try {
    $env:USERPROFILE = $homeDir
    $env:PATH = "$bin;$env:PATH"
    $env:PATHEXT = ".PS1;$env:PATHEXT"
    $env:PSMUX_DATA_DIR = $data
    $env:PSMUX_ALLOW_NESTING = '1'
    foreach ($v in 'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE') {
        [Environment]::SetEnvironmentVariable($v, $null, 'Process')
    }
    Invoke-Psmux new-session -d -s keep -c $homeDir | Out-Null
    Invoke-Psmux new-session -d -s target -c $homeDir | Out-Null
    if (-not (Wait-Until {
        & $wrapper has-session -t target 2>$null
        $LASTEXITCODE -eq 0
    })) { throw 'target session did not start' }
    Invoke-Psmux split-window -t 'target:0' -c $homeDir | Out-Null
    if (-not (Wait-Until {
        @(Invoke-Psmux list-panes -t 'target:0' -F '#{pane_pid}').Count -eq 2
    })) { throw 'target split did not appear' }
    $live = @(Invoke-Psmux list-panes -t 'target:0' -F '#{pane_pid}|#{pane_current_command}')
    Check 'fixture has two panes with real process ids' `
        ($live.Count -eq 2 -and @($live | Where-Object { $_ -notmatch '^\d+\|\S+' }).Count -eq 0) ($live -join ', ')
    if ($fail) { throw 'fixture failed' }
    $out = & pwsh -NoProfile -File (Join-Path $plugin 'scripts\save.ps1') 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "save failed: $out" }
    $last = Join-Path $homeDir '.psmux\resurrect\last'
    if (-not (Test-Path $last)) { throw "save missing: $out" }
    $saved = Get-Content ((Get-Content $last -Raw).Trim()) -Raw | ConvertFrom-Json
    $target = @($saved.sessions | Where-Object name -eq 'target')
    Check 'snapshot includes target and keeper' `
        ($target.Count -eq 1 -and @($saved.sessions.name) -contains 'keep')
    Check 'snapshot includes both target panes' ($target[0].windows[0].panes.Count -eq 2)
    foreach ($line in $live) {
        $panePid, $command = $line -split '\|', 2
        $marker = Join-Path $homeDir "restored-$panePid.txt"
        Check "save captured resumable command for pid $panePid" `
            (@($target[0].windows[0].panes.command | Where-Object { $_.Contains("restored-$panePid.txt") }).Count -eq 1)
        Check "restore marker for pid $panePid is initially absent" (-not (Test-Path $marker))
    }
    Invoke-Psmux kill-session -t target | Out-Null
    if (-not (Wait-Until {
        & $wrapper has-session -t target 2>$null
        $LASTEXITCODE -ne 0
    })) { throw 'target did not stop' }
    Check 'keeper survives while target is absent' (@(Invoke-Psmux list-sessions -F '#{session_name}') -contains 'keep')
    $out = & pwsh -NoProfile -File (Join-Path $plugin 'scripts\restore.ps1') 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "restore failed: $out" }
    Check 'restore recreates target' (@(Invoke-Psmux list-sessions -F '#{session_name}') -contains 'target') $out
    Check 'restore recreates both panes' (@(Invoke-Psmux list-panes -t 'target:0' -F '#{pane_id}').Count -eq 2) $out
    foreach ($line in $live) {
        $panePid, $command = $line -split '\|', 2
        $marker = Join-Path $homeDir "restored-$panePid.txt"
        $created = Wait-Until { Test-Path $marker }
        Check "restore executes persisted command for pid $panePid" $created $out
        if ($created) {
            Check "restored command retains original command and pid $panePid" `
                ((Get-Content $marker -Raw).Trim() -ceq "$command|$panePid")
        }
    }
}
finally {
    try {
        & $wrapper kill-server 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning 'test namespace cleanup failed' }
    }
    finally {
        foreach ($v in $vars) { [Environment]::SetEnvironmentVariable($v, $old[$v], 'Process') }
        Remove-Item $sandbox -Recurse -Force
    }
}
Write-Host "Results: $pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
