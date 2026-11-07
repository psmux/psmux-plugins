#!/usr/bin/env pwsh
# Disposable Windows only: claims the per-user restore mutex; uses fake psmux.
$ErrorActionPreference = 'Stop'
$restore = Join-Path (Split-Path $PSScriptRoot -Parent) 'psmux-resurrect\scripts\restore.ps1'
$root = Join-Path $env:TEMP ('restore-mutex-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $root 'bin'
$homeDir = Join-Path $root 'home'
$saveDir = Join-Path $homeDir '.psmux\resurrect'
$log = Join-Path $root 'calls.txt'
$entered = Join-Path $root 'entered'
$release = Join-Path $root 'release'
$pass = 0
$jobs = [Collections.Generic.List[object]]::new()
function Check($name, $condition) {
    if (-not $condition) { throw "FAIL: $name" }
    $script:pass++; Write-Host "PASS: $name"
}
function Wait-For([scriptblock]$condition) {
    $deadline = (Get-Date).AddSeconds(15)
    do {
        if (& $condition) { return }
        Start-Sleep -Milliseconds 50
    } while ((Get-Date) -lt $deadline)
    throw 'Timed out waiting for test precondition.'
}
function Start-Restore {
    $si = [Diagnostics.ProcessStartInfo]::new()
    $si.FileName = (Get-Command pwsh).Source
    foreach ($arg in @('-NoProfile', '-File', $restore)) { $si.ArgumentList.Add($arg) }
    $si.UseShellExecute = $false
    $si.RedirectStandardOutput = $true; $si.RedirectStandardError = $true
    $si.Environment['USERPROFILE'] = $homeDir
    $si.Environment['PATH'] = "$bin;$env:PATH"
    $si.Environment['PATHEXT'] = ".PS1;$env:PATHEXT"
    $si.Environment['MUTEX_TEST_ROOT'] = $root
    $p = [Diagnostics.Process]::new(); $p.StartInfo = $si
    [void]$p.Start()
    $job = @{Process=$p;Out=$p.StandardOutput.ReadToEndAsync();Err=$p.StandardError.ReadToEndAsync()}
    $jobs.Add($job)
    $job
}
function Finish($job) {
    if (-not $job.Process.WaitForExit(20000)) { throw 'Restore did not finish.' }
    @{Exit=$job.Process.ExitCode;Out=$job.Out.GetAwaiter().GetResult();Err=$job.Err.GetAwaiter().GetResult()}
}
$mutexName = "Global\psmux-resurrect-restore-$([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)"
$observer = [Threading.Mutex]::new($false, $mutexName)
try {
    Check 'no other restore is active before the test' ($observer.WaitOne(0))
    $observer.ReleaseMutex()
    New-Item -ItemType Directory $bin, $saveDir -Force | Out-Null
    @'
$ErrorActionPreference = 'Stop'
$root = $env:MUTEX_TEST_ROOT
Add-Content (Join-Path $root 'calls.txt') ($args -join ' ')
if ($args[0] -eq 'show-options') {
    switch ($args[-1]) {
        '@resurrect-dir' { exit 1 }
        '@resurrect-processes' {
            New-Item -ItemType File (Join-Path $root 'entered') -Force | Out-Null
            $deadline = (Get-Date).AddSeconds(15)
            while (-not (Test-Path (Join-Path $root 'release'))) {
                if ((Get-Date) -gt $deadline) { throw 'Test owner was never released.' }
                Start-Sleep -Milliseconds 25
            }
            'false'; exit 0
        }
        '@resurrect-overwrite' { 'off'; exit 0 }
    }
}
exit 0
'@ | Set-Content (Join-Path $bin 'psmux.ps1')
    $snapshot = Join-Path $saveDir 'snapshot.json'
    '{"version":2,"sessions":[]}' | Set-Content $snapshot
    Set-Content (Join-Path $saveDir 'last') $snapshot
    $owner = Start-Restore
    Wait-For { Test-Path $entered }
    Check 'owner acquired mutex before entering restore' (-not $observer.WaitOne(0))
    $before = @(Get-Content $log).Count
    $contender = Finish (Start-Restore)
    $newCalls = @(Get-Content $log | Select-Object -Skip $before)
    Check 'overlapping restore exits successfully with an explicit skip' ($contender.Exit -eq 0 -and $contender.Out -match 'another restore is in progress' -and -not $contender.Err)
    Check 'skipped restore makes only its initial directory query' ($newCalls.Count -eq 1 -and $newCalls[0] -eq 'show-options -gv @resurrect-dir')
    Check 'skipped restore leaves the owner running' (-not $owner.Process.HasExited)
    New-Item -ItemType File $release | Out-Null
    $finished = Finish $owner
    Check 'owner completes normally' ($finished.Exit -eq 0 -and -not $finished.Err)
    Check 'normal completion releases the mutex' ($observer.WaitOne(0))
    $observer.ReleaseMutex()

    Remove-Item $entered, $release
    $owner = Start-Restore
    Wait-For { Test-Path $entered }
    Check 'crash victim owns the mutex' (-not $observer.WaitOne(0))
    Stop-Process -Id $owner.Process.Id -Force
    $killed = Finish $owner
    Check 'owner was forcibly stopped' ($killed.Exit -ne 0)
    # The observer keeps the named object alive; the next restore must handle abandonment.
    New-Item -ItemType File $release | Out-Null
    $recovered = Finish (Start-Restore)
    Check 'next restore accepts an abandoned mutex' ($recovered.Exit -eq 0 -and $recovered.Out -notmatch 'in progress' -and -not $recovered.Err)

    # A snapshot read error happens after acquisition in the real restore script.
    Remove-Item $snapshot
    New-Item -ItemType Directory $snapshot | Out-Null
    $failed = Finish (Start-Restore)
    Check 'fixture causes a snapshot read error after acquisition' ($failed.Err -match 'Get-Content')
    Check 'snapshot read error releases the mutex' ($observer.WaitOne(0))
    $observer.ReleaseMutex()
    Remove-Item $snapshot
    '{"version":2,"sessions":[]}' | Set-Content $snapshot
    $afterError = Finish (Start-Restore)
    Check 'restore proceeds after the error without cleanup files' ($afterError.Exit -eq 0 -and $afterError.Out -notmatch 'in progress' -and -not $afterError.Err)
} finally {
    foreach ($job in $jobs) {
        if (-not $job.Process.HasExited) { Stop-Process -Id $job.Process.Id -Force }
        $job.Process.Dispose()
    }
    $observer.Dispose()
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
}
Write-Host "Results: $pass passed"
