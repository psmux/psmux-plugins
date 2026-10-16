#!/usr/bin/env pwsh
# Real capture/retry checks. Run only in a disposable Windows environment.
# Private namespace, data root and profile; cleanup targets that namespace.
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check($name, $condition, $detail = '') {
    if ($condition) { Write-Host "  PASS: $name"; $script:pass++ }
    else { Write-Host "  FAIL: $name >> $detail"; $script:fail++ }
}
$real = (Get-Command psmux -CommandType Application -ErrorAction Stop).Source
$save = Join-Path (Split-Path $PSScriptRoot -Parent) 'psmux-resurrect\scripts\save.ps1'
$root = Join-Path $env:TEMP ('capture-e2e-' + [guid]::NewGuid().ToString('N'))
$homeDir = Join-Path $root 'home'
$bin = Join-Path $root 'bin'
$data = Join-Path $root 'data'
New-Item -ItemType Directory $homeDir, $bin, $data -Force | Out-Null
$ns = 'capture_' + [guid]::NewGuid().ToString('N')
$config = Join-Path $root 'psmux.conf'
@'
set -g default-shell pwsh
set -g default-command 'pwsh -NoLogo -NoProfile'
set -g @resurrect-capture-pane-contents on
set -g automatic-rename off
'@ | Set-Content $config
$wrapper = Join-Path $bin 'psmux.ps1'
@'
function Invoke-RealQuery([string[]]$arguments) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $env:CAPTURE_REAL
    foreach ($argument in (@('-L', $env:CAPTURE_NS, '-f', $env:CAPTURE_CONFIG) + $arguments)) { $info.ArgumentList.Add($argument) }
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return @{ Output = $stdout.GetAwaiter().GetResult(); Error = $stderr.GetAwaiter().GetResult(); Exit = $process.ExitCode }
    } finally { $process.Dispose() }
}
$a = @($args)
$response = Invoke-RealQuery $a
$out = @($response.Output -split "`n" | Where-Object { $_ })
$code = $response.Exit
if ($a[0] -eq 'list-sessions') {
    'sessions' | Add-Content (Join-Path $env:CAPTURE_ROOT 'queries')
    if ($env:CAPTURE_CASE -eq 'close-session' -and $out -contains 'target') {
        & $env:CAPTURE_REAL -L $env:CAPTURE_NS -f $env:CAPTURE_CONFIG kill-session -t target 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Session closure failed.' }
    }
}
if ($a[0] -eq 'list-panes' -and $env:CAPTURE_CASE -eq 'persistent' -and $a -contains 'target') {
    # Each attempt sees target, which exits before its structural query.
    & $env:CAPTURE_REAL -L $env:CAPTURE_NS -f $env:CAPTURE_CONFIG kill-session -t target 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Persistent boundary closure failed.' }
    $response = Invoke-RealQuery $a
    $out = @($response.Output -split "`n" | Where-Object { $_ })
    $code = $response.Exit
    & $env:CAPTURE_REAL -L $env:CAPTURE_NS -f $env:CAPTURE_CONFIG new-session -d -s target 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Persistent fixture recreation failed.' }
}
if ($a[0] -eq 'list-panes' -and $a -contains 'target' -and $env:CAPTURE_CASE -eq 'optional-content') {
    & $env:CAPTURE_REAL -L $env:CAPTURE_NS -f $env:CAPTURE_CONFIG kill-window -t target:1 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Optional-content boundary closure failed.' }
}
[ordered]@{args=$a;exit=$code;output=@($out | ForEach-Object { "$_" })} | ConvertTo-Json -Compress -Depth 5 | Add-Content (Join-Path $env:CAPTURE_ROOT 'trace')
if ($a[0] -eq 'list-panes' -and $a -contains '-s') { [Console]::Write($response.Output) }
else { $out }
[Console]::Error.Write($response.Error)
exit $code
'@ | Set-Content $wrapper
$vars = @('USERPROFILE','PATH','PATHEXT','PSMUX_DATA_DIR','PSMUX_ALLOW_NESTING',
    'PSMUX_SESSION','PSMUX_SESSION_NAME','PSMUX_TARGET_SESSION','TMUX','TMUX_PANE',
    'CAPTURE_REAL','CAPTURE_NS','CAPTURE_CONFIG','CAPTURE_ROOT','CAPTURE_CASE')
$old = @{}
foreach ($v in $vars) { $old[$v] = [Environment]::GetEnvironmentVariable($v,'Process') }
function Real {
    $out = & $real -L $ns -f $config @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "psmux $args failed: $out" }
    $out
}
function RunSave([string]$mode) {
    $env:CAPTURE_CASE = $mode
    Remove-Item "$root\queries", "$root\trace" -ErrorAction SilentlyContinue
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $out = & pwsh -NoProfile -File $save 2>&1 | Out-String
    $code = $LASTEXITCODE
    $timer.Stop()
    [pscustomobject]@{Exit=$code;Output=$out;Seconds=$timer.Elapsed.TotalSeconds;Attempts=@(Get-Content "$root\queries").Count;Trace=@(Get-Content "$root\trace" | ForEach-Object { $_ | ConvertFrom-Json })}
}
function Snapshot {
    Get-Content ((Get-Content "$homeDir\.psmux\resurrect\last" -Raw).Trim()) -Raw | ConvertFrom-Json
}
try {
    $env:USERPROFILE=$homeDir; $env:PATH="$bin;$env:PATH"; $env:PATHEXT=".PS1;$env:PATHEXT"
    $env:PSMUX_DATA_DIR=$data; $env:PSMUX_ALLOW_NESTING='1'
    foreach ($v in 'PSMUX_SESSION','PSMUX_SESSION_NAME','PSMUX_TARGET_SESSION','TMUX','TMUX_PANE') { [Environment]::SetEnvironmentVariable($v,$null,'Process') }
    $env:CAPTURE_REAL=$real; $env:CAPTURE_NS=$ns; $env:CAPTURE_CONFIG=$config; $env:CAPTURE_ROOT=$root
    Real new-session -d -s keep | Out-Null
    Real new-session -d -s target | Out-Null
    Real new-window -t target:1 -n split | Out-Null
    Real split-window -t target:1 | Out-Null
    $paneIds = @(Real list-panes -t target:1 -F '#{pane_id}')
    Check 'split fixture has two identifiable panes' ($paneIds.Count -eq 2)
    $title = "build`t123\npath\literal's `"quoted`" | value"
    Real select-pane -t $paneIds[0] -T $title | Out-Null
    $titleRows = @(Real list-panes -t target:1 -F '#{pane_id}|#{pane_title}' | Where-Object { ($_ -split '\|', 2)[0] -eq $paneIds[0] })
    Check 'pane title fixture is present before capture' ($titleRows.Count -eq 1 -and ($titleRows[0] -split '\|', 2)[1] -ceq $title) ($titleRows -join ', ')
    Real resize-pane -Z -t target:1 | Out-Null
    $windows = @(Real list-windows -t target -F '#{window_index}')
    Check 'fixture has two windows before capture' ($windows.Count -eq 2)
    $r = RunSave 'stable'
    Check 'stable save succeeds on first attempt' ($r.Exit -eq 0 -and $r.Attempts -eq 1) $r.Output
    if ($r.Exit -ne 0) { throw "Stable save failed: $($r.Output)`nTrace: $($r.Trace | ConvertTo-Json -Depth 6)" }
    $obj = Snapshot
    $target = $obj.sessions | Where-Object name -eq target
    Check 'single-query capture preserves both windows and split panes' ($target.windows.Count -eq 2 -and ($target.windows | Where-Object index -eq 1).panes.Count -eq 2)
    Check 'single-query capture preserves zoom state' (($target.windows | Where-Object index -eq 1).zoomed)
    Check 'captured pane commands and indices are valid' (@($obj.sessions.windows.panes | Where-Object { $null -eq $_.index -or -not $_.command }).Count -eq 0)
    Check 'real quoted format preserves tabs, quotes and backslashes in pane titles' `
        (@($target.windows.panes | Where-Object { $_.title -ceq $title }).Count -eq 1) `
        ("Expected: $($title | ConvertTo-Json -Compress); actual: $($target.windows.panes.title | ConvertTo-Json -Compress); query: $($r.Trace | Where-Object { $_.args[0] -eq 'list-panes' } | ConvertTo-Json -Depth 5 -Compress)")
    Start-Sleep -Milliseconds 1100
    $r = RunSave 'close-session'
    $obj = Snapshot
    Check 'real session disappearance triggers one full retry' ($r.Exit -eq 0 -and $r.Attempts -eq 2 -and $r.Seconds -ge 2 -and @($r.Trace | Where-Object { $_.args[0] -eq 'list-panes' -and $_.exit -ne 0 }).Count -eq 1) $r.Output
    Check 'retry saves the surviving session without a phantom empty session' ($obj.sessions.Count -eq 1 -and $obj.sessions[0].name -eq 'keep')
    Real new-session -d -s target | Out-Null
    Real new-window -t target:1 | Out-Null
    $r = RunSave 'optional-content'
    $target = (Snapshot).sessions | Where-Object name -eq target
    $missing = ($target.windows | Where-Object index -eq 1).panes[0]
    Check 'optional-content failure does not retry structural capture' ($r.Exit -eq 0 -and $r.Attempts -eq 1 -and @($r.Trace | Where-Object { $_.args[0] -eq 'capture-pane' -and $_.exit -ne 0 }).Count -gt 0)
    Check 'failed optional capture does not persist error text as contents' ($missing.PSObject.Properties.Name -notcontains 'content')
    $last = "$homeDir\.psmux\resurrect\last"
    $lastHash = (Get-FileHash $last).Hash
    $goodPath = (Get-Content $last -Raw).Trim()
    $goodHash = (Get-FileHash $goodPath).Hash
    $count = @(Get-ChildItem (Split-Path $last) -Filter *.json).Count
    $r = RunSave 'persistent'
    Check 'persistent real query failures exhaust four attempts and 12 seconds of backoff' ($r.Exit -ne 0 -and $r.Attempts -eq 4 -and $r.Seconds -ge 12 -and @($r.Trace | Where-Object { $_.args[0] -eq 'list-panes' -and $_.exit -ne 0 }).Count -eq 4) $r.Output
    Check 'exhausted retries preserve last and its snapshot byte-for-byte' ((Get-FileHash $last).Hash -eq $lastHash -and (Get-FileHash $goodPath).Hash -eq $goodHash)
    Check 'exhausted retries create no new snapshots' (@(Get-ChildItem (Split-Path $last) -Filter *.json).Count -eq $count)
} finally {
    & $real -L $ns -f $config kill-server 2>&1 | Out-Null
    foreach ($v in $vars) { [Environment]::SetEnvironmentVariable($v,$old[$v],'Process') }
    Remove-Item $root -Recurse -Force
}
Write-Host "Results: $pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
