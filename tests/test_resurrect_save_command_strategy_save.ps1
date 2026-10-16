#!/usr/bin/env pwsh
# Save wiring regression tests with a fake psmux and an isolated user profile.
# No real servers or user options are accessed.
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL: $name >> $detail" -ForegroundColor Red; $script:fail++ }
}
$plugin = Join-Path (Split-Path $PSScriptRoot -Parent) 'psmux-resurrect'
$save = Join-Path $plugin 'scripts\save.ps1'
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('save-wiring-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $sandbox 'bin'
New-Item -ItemType Directory $bin -Force | Out-Null
@'
switch ($args[0]) {
    'show-options' {
        if ($args -contains '@resurrect-save-command-strategy') { $env:TEST_SAVE_STRATEGY }
        exit 0
    }
    'list-sessions' { 'work'; '0'; '1'; '__warm__'; exit 0 }
    'list-windows' { throw 'Window metadata comes from list-panes -s.' }
    'list-panes' {
        $row = (@(0, 'main', 1, 'c2be,80x24,0,0,1', 0, '', 0, $env:USERPROFILE, 1, 'shell', 4567, 'pwsh') | ForEach-Object { ([string]$_).Replace('\', '\\') }) -join "`t"
        [Console]::Write($row + "`n")
        if ($args -contains '1') {
            $row = (@(0, 'main', 1, 'c2be,80x24,0,0,1', 0, '', 1, $env:USERPROFILE, 0, 'second', 4568, 'pwsh') | ForEach-Object { ([string]$_).Replace('\', '\\') }) -join "`t"
            [Console]::Write($row + "`n")
        }
        exit 0
    }
    default { exit 0 }
}
'@ | Set-Content (Join-Path $bin 'psmux.ps1')

function Invoke-SaveCase([string]$strategy, [string]$body) {
    $homeDir = Join-Path $sandbox ([guid]::NewGuid().ToString('N'))
    $strategyDir = Join-Path $homeDir '.psmux\strategies\save_command_strategies'
    New-Item -ItemType Directory $strategyDir -Force | Out-Null
    Set-Content (Join-Path $strategyDir 'rewrite.ps1') $body
    $vars = @('USERPROFILE', 'PATH', 'PATHEXT', 'TEST_SAVE_STRATEGY')
    $old = @{}
    foreach ($v in $vars) { $old[$v] = [Environment]::GetEnvironmentVariable($v, 'Process') }
    try {
        $env:USERPROFILE = $homeDir
        $env:PATH = "$bin;$env:PATH"
        $env:PATHEXT = ".PS1;$env:PATHEXT"
        $env:TEST_SAVE_STRATEGY = $strategy
        $out = & pwsh -NoProfile -File $save 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "save failed: $out" }
        $last = Join-Path $homeDir '.psmux\resurrect\last'
        if (-not (Test-Path $last)) { throw "save missing: $out" }
        Get-Content ((Get-Content $last -Raw).Trim()) -Raw | ConvertFrom-Json
    }
    finally {
        foreach ($v in $vars) { [Environment]::SetEnvironmentVariable($v, $old[$v], 'Process') }
    }
}
function Find-WorkCommand($snapshot) {
    ($snapshot.sessions | Where-Object name -eq 'work').windows[0].panes[0].command
}
try {
    $sentinel = Join-Path $sandbox 'strategy-invocations.txt'
    $strategy = @"
param([string]`$Command, [string]`$PanePid, [string]`$Directory)
"`$Command|`$PanePid|`$Directory" | Add-Content -LiteralPath '$sentinel'
"tool --resume=`$PanePid"
"@
    $plain = Invoke-SaveCase '' $strategy
    Check 'unset strategy keeps bare commands' ((Find-WorkCommand $plain) -ceq 'pwsh')
    Check 'unset strategy invokes no script' (-not (Test-Path $sentinel))
    Check 'untouched numeric session is excluded' (@($plain.sessions.name) -notcontains '0')
    Check 'shaped numeric session is included' (@($plain.sessions.name) -contains '1')
    Check 'internal session is excluded' (@($plain.sessions.name) -notcontains '__warm__')

    $rewritten = Invoke-SaveCase 'rewrite' $strategy
    $command = Find-WorkCommand $rewritten
    Check 'save persists transformed command with pane pid' ($command -ceq 'tool --resume=4567') $command
    Check 'strategy sees original command, pid and pane directory' `
        ((Test-Path $sentinel) -and ((Get-Content $sentinel -Raw) -match 'pwsh\|4567\|'))
    Check 'strategy preserves unnamed-session filtering' (@($rewritten.sessions.name) -notcontains '0')
    Check 'shaped numeric session gets transformed commands' `
        (($rewritten.sessions | Where-Object name -eq '1').windows[0].panes[1].command -ceq 'tool --resume=4568')
    $calls = @(if (Test-Path $sentinel) { Get-Content $sentinel })
    Check 'strategy runs once per saved pane, excluding filtered sessions' ($calls.Count -eq 3) "calls=$($calls.Count)"
    $panes = @($rewritten.sessions | ForEach-Object { $_.windows | ForEach-Object panes })
    Check 'pane pid is not added to the persisted schema' `
        (@($panes | Where-Object { $_.PSObject.Properties.Name -contains 'pid' }).Count -eq 0)
    Check 'snapshot format version stays at 2' ($rewritten.version -eq 2)

    $failed = Invoke-SaveCase 'rewrite' 'Write-Output WRONG_COMMAND; exit 7'
    Check 'save persists original command when strategy fails after output' ((Find-WorkCommand $failed) -ceq 'pwsh')
}
finally {
    Remove-Item $sandbox -Recurse -Force
}
Write-Host "Results: $pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
