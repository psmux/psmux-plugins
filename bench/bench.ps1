#!/usr/bin/env pwsh
# =============================================================================
# psmux-plugins benchmark
#
#   pwsh -NoProfile -File bench/bench.ps1 [-Repo <checkout>] [-Label <name>]
#
# Measures what the plugins cost a psmux user, against the plugin code in
# -Repo (default: this checkout), so two checkouts can be compared on one
# machine:
#   nav    C-h/C-l to pane switch with psmux-vim-navigator loaded (ms)
#   type   a typed character to its echo, same setup (ms)
#   idle   CPU used by the server and plugin helper processes while idle
#   save   psmux-resurrect save.ps1 wall time, 3 sessions x 3 windows x 2 panes
#   theme  start to theme options visible, psmux-theme-nord through @plugin
# Keys go in through WriteConsoleInput on a real attached client (bench/keylat.cs)
# and the result is read off that client's console, so the numbers are what
# a user sees.
#
# Everything runs in a temporary USERPROFILE: psmux keeps its sockets, config
# and plugin directory there, so the user's own server and sessions are never
# touched. Raw samples and a summary go to -OutDir, by default
# ~/psmux-bench/psmux-plugins/<date>/.
# =============================================================================
param(
    [string]$Repo = (Split-Path $PSScriptRoot -Parent),
    [string]$Label = 'current',
    [string]$OutDir,
    [int]$Samples = 80,
    # Pause after each nav/type sample. psmux caches the process table a key
    # binding's #{pane_current_command} reads for 250 ms, so a gap above that
    # makes every key pay for a fresh walk, as keys spaced by a person do.
    [int]$GapMs = 150,
    [int]$IdleSeconds = 30,
    [int]$SaveRuns = 5,
    [string[]]$Scenarios = @('nav', 'type', 'idle', 'save', 'theme')
)
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path $Repo).Path
if (-not $OutDir) { $OutDir = Join-Path $HOME ('psmux-bench\psmux-plugins\' + (Get-Date -Format 'yyyy-MM-dd')) }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$psmux = (Get-Command psmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$pwshExe = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$work = Join-Path ([IO.Path]::GetTempPath()) ('psmux-bench-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
# keylat is compiled in memory by a child pwsh (Add-Type) and never written
# out as an .exe: Defender's ML heuristics quarantine a fresh exe that writes
# into another console's input (Trojan:Win32/Bearfoos.A!ml), and the next
# run then fails to start it.
$keylatSrc = Join-Path $PSScriptRoot 'keylat.cs'
function Invoke-KeyLatProbe([string[]]$argv) {
    $list = ($argv | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
    & $pwshExe -NoProfile -Command "Add-Type -Path '$keylatSrc'; exit [KeyLat]::Main(@($list))"
}

$saved = @{}
foreach ($v in 'USERPROFILE', 'HOME', 'PSMUX_DATA_DIR', 'PSMUX_ALLOW_NESTING', 'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE') {
    $saved[$v] = [Environment]::GetEnvironmentVariable($v)
}
foreach ($v in 'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }

$results = [Collections.Generic.List[object]]::new()
$machine = [ordered]@{
    psmux = (& $psmux -V 2>&1 | Select-Object -Last 1) -join ''
    pwsh = $PSVersionTable.PSVersion.ToString()
    os = [Environment]::OSVersion.VersionString
    cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    logical_cpus = [Environment]::ProcessorCount
    commit = (git -C $Repo rev-parse --short HEAD 2>$null)
    gap_ms = $GapMs
}

function Get-Stats([double[]]$xs) {
    if (-not $xs -or $xs.Count -eq 0) { return @{ n = 0 } }
    $s = $xs | Sort-Object
    $pct = { param($p) $s[[Math]::Min($s.Count - 1, [int][Math]::Floor($p * $s.Count))] }
    [ordered]@{ n = $s.Count; mean = [Math]::Round(($s | Measure-Object -Average).Average, 3)
        p50 = & $pct 0.5; p90 = & $pct 0.9; p99 = & $pct 0.99; max = $s[-1] }
}

function Add-Result([string]$scenario, [string]$metric, [string]$unit, $values, [string]$note = '') {
    $vals = @($values | Where-Object { $_ -ne $null } | ForEach-Object { [double]$_ })
    $st = Get-Stats $vals
    $row = [ordered]@{ label = $Label; scenario = $scenario; metric = $metric; unit = $unit }
    foreach ($k in $st.Keys) { $row[$k] = $st[$k] }
    $row.note = $note
    $results.Add([pscustomobject]$row)
    $raw = Join-Path $OutDir "$Label-$scenario-$metric.csv"
    (@('value') + ($vals | ForEach-Object { $_.ToString([Globalization.CultureInfo]::InvariantCulture) })) | Set-Content $raw
    Write-Host ("  {0,-6} {1,-26} n={2,-3} p50={3} p90={4} max={5} {6} {7}" -f $scenario, $metric, $st.n, $st.p50, $st.p90, $st.max, $unit, $note)
}

# A fresh home per scenario, so nothing one leaves running affects the next.
function Enter-Home([string]$name) {
    $h = Join-Path $work "home-$name"
    $plugins = Join-Path $h '.psmux\plugins'
    New-Item -ItemType Directory -Force $plugins, (Join-Path $h '.psmux\resurrect'), (Join-Path $h 'data') | Out-Null
    Get-ChildItem $Repo -Directory | Where-Object { $_.Name -like 'psmux-*' } | ForEach-Object {
        New-Item -ItemType Junction -Path (Join-Path $plugins $_.Name) -Target $_.FullName | Out-Null
    }
    $env:USERPROFILE = $h; $env:HOME = $h
    $env:PSMUX_DATA_DIR = Join-Path $h 'data'; $env:PSMUX_ALLOW_NESTING = '1'
    $script:CurrentHome = $h
    return $h
}

function Exit-Home {
    $h = $script:CurrentHome
    if (-not $h) { return }
    & $psmux kill-server 2>&1 | Out-Null
    # Plugin helpers this scenario started (vim-navigator's old poller, theme
    # scripts) carry the sandbox home in their command line.
    $needles = @($h, ($h -replace '\\', '/'))
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='conhost.exe' OR Name='psmux.exe'" | Where-Object {
        $cl = $_.CommandLine; $cl -and ($needles | Where-Object { $cl.Contains($_) })
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $lock = Join-Path $h '.psmux\vim-navigator.pid'
    if (Test-Path $lock) {
        $p = (Get-Content $lock -Raw).Trim()
        if ($p -match '^\d+$') {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$p" -ErrorAction SilentlyContinue
            if ($proc -and $proc.CommandLine -match 'poll-vim-state') { Stop-Process -Id ([int]$p) -Force -ErrorAction SilentlyContinue }
        }
    }
    Start-Sleep -Milliseconds 500
    Get-ChildItem (Join-Path $h '.psmux\plugins') -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType -eq 'Junction' } | ForEach-Object { $_.Delete() }
    $script:CurrentHome = $null
}

function Wait-Session([string]$name) {
    for ($i = 0; $i -lt 60; $i++) {
        & $psmux has-session -t $name 2>$null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Milliseconds 250
    }
    throw "session $name did not start"
}

function Start-NavigatorSetup {
    & $psmux new-session -d -s bench -c 'C:\' 2>&1 | Out-Null
    Wait-Session bench
    & $psmux split-window -h -t bench -c 'C:\' 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    & $psmux select-pane -t 'bench:.0' 2>&1 | Out-Null
    & $pwshExe -NoProfile -File (Join-Path $Repo 'psmux-vim-navigator\psmux-vim-navigator.ps1') 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}

function Invoke-KeyLat([string]$mode) {
    $con = Start-Process conhost.exe -ArgumentList "`"$psmux`" attach -t bench" -PassThru
    Start-Sleep -Seconds 4
    $client = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($con.Id)" | Select-Object -First 1
    if (-not $client) { throw 'attached client did not start' }
    $out = Join-Path $work "keylat-$mode.txt"
    Invoke-KeyLatProbe @("$($client.ProcessId)", $mode, "$Samples", $out, "$GapMs")
    $lines = @(Get-Content $out)
    if ($lines[0] -like 'error*') { throw "keylat: $($lines[0])" }
    & $psmux detach-client -a 2>&1 | Out-Null
    if (-not $con.HasExited) { Stop-Process -Id $con.Id -Force -ErrorAction SilentlyContinue }
    $timeouts = @($lines | Where-Object { $_ -eq 'timeout' }).Count
    return @{ values = @($lines | Where-Object { $_ -ne 'timeout' }); timeouts = $timeouts }
}

try {
    Write-Host "psmux-plugins bench: $Label ($Repo @ $($machine.commit))" -ForegroundColor Cyan

    foreach ($mode in @('nav', 'type') | Where-Object { $Scenarios -contains $_ }) {
        Enter-Home $mode | Out-Null
        try {
            Start-NavigatorSetup
            $r = Invoke-KeyLat $mode
            $metric = if ($mode -eq 'nav') { 'nav_key_to_pane_switch' } else { 'char_key_to_echo' }
            Add-Result $mode $metric 'ms' $r.values "timeouts=$($r.timeouts)"
        } finally { Exit-Home }
    }

    if ($Scenarios -contains 'idle') {
        $h = Enter-Home 'idle'
        try {
            Start-NavigatorSetup
            Start-Sleep -Seconds 3
            # The server, plus long-lived helpers whose command line names this
            # sandbox (vim-navigator's old poller passes its lock file path).
            $serverPid = [int]((& $psmux display -p '#{pid}' 2>&1 | Out-String).Trim())
            $ids = @($serverPid) + @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object {
                $_.CommandLine -and ($_.CommandLine.Contains($h) -or $_.CommandLine.Contains(($h -replace '\\', '/')))
            } | ForEach-Object { [int]$_.ProcessId })
            $mine = @($ids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
            $t0 = @{}; foreach ($p in $mine) { $t0[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds }
            $sw = [Diagnostics.Stopwatch]::StartNew()
            Start-Sleep -Seconds $IdleSeconds
            $cpu = 0.0
            foreach ($p in $mine) { try { $p.Refresh(); $cpu += $p.TotalProcessorTime.TotalMilliseconds - $t0[$p.Id] } catch {} }
            $wall = $sw.Elapsed.TotalMilliseconds
            $names = ($mine | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ' '
            Add-Result 'idle' 'cpu_ms_per_second' 'ms/s' @([Math]::Round($cpu / ($wall / 1000), 3)) "long-lived processes: $names; short-lived psmux calls not counted"
        } finally { Exit-Home }
    }

    if ($Scenarios -contains 'save') {
        $h = Enter-Home 'save'
        try {
            foreach ($s in 1..3) {
                & $psmux new-session -d -s "work$s" -c 'C:\' 2>&1 | Out-Null
                Wait-Session "work$s"
                foreach ($w in 1..3) {
                    if ($w -gt 1) { & $psmux new-window -t "work$s" -c 'C:\' 2>&1 | Out-Null }
                    & $psmux split-window -h -t "work$s" -c 'C:\' 2>&1 | Out-Null
                }
            }
            Start-Sleep -Seconds 3
            $save = Join-Path $Repo 'psmux-resurrect\scripts\save.ps1'
            $times = foreach ($i in 1..$SaveRuns) {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                & $pwshExe -NoProfile -File $save 2>&1 | Out-Null
                $sw.Elapsed.TotalMilliseconds
            }
            $files = @(Get-ChildItem (Join-Path $h '.psmux\resurrect') -Filter 'psmux_resurrect_*.json' -ErrorAction SilentlyContinue)
            Add-Result 'save' 'save_wall_time' 'ms' $times "snapshots written=$($files.Count)"
        } finally { Exit-Home }
    }

    if ($Scenarios -contains 'theme') {
        $times = @(); $never = 0
        foreach ($i in 1..3) {
            $h = Enter-Home "theme$i"
            try {
                "set -g @nord-show-user 'off'`nset -g @plugin 'psmux-plugins/psmux-theme-nord'" | Set-Content (Join-Path $h '.psmux.conf')
                $sw = [Diagnostics.Stopwatch]::StartNew()
                & $psmux new-session -d -s bench -c 'C:\' 2>&1 | Out-Null
                $done = $false
                while ($sw.ElapsedMilliseconds -lt 20000) {
                    $len = (& $psmux show-options -gv status-left-length 2>&1 | Out-String).Trim()
                    if ($len -eq '45') { $times += $sw.Elapsed.TotalMilliseconds; $done = $true; break }
                    Start-Sleep -Milliseconds 50
                }
                if (-not $done) { $never++ }
            } finally { Exit-Home }
        }
        Add-Result 'theme' 'options_visible_after_start' 'ms' $times "never within 20 s: $never of 3"
    }
}
finally {
    if ($script:CurrentHome) { Exit-Home }
    foreach ($v in $saved.Keys) { [Environment]::SetEnvironmentVariable($v, $saved[$v]) }
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

$summary = [ordered]@{ label = $Label; repo = $Repo; when = (Get-Date).ToString('o'); machine = $machine; results = $results }
$summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir "$Label-summary.json")
$csv = Join-Path $OutDir 'summary.csv'
$results | Select-Object label, scenario, metric, unit, n, mean, p50, p90, p99, max, note |
    Export-Csv $csv -NoTypeInformation -Append
Write-Host "Results in $OutDir" -ForegroundColor Cyan
