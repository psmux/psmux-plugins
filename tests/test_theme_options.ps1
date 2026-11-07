#!/usr/bin/env pwsh
# =============================================================================
# Theme options must apply however the theme is loaded (issue #42).
#
# psmux auto-sources a plugin's plugin.conf when it reads `set -g @plugin`,
# which is how PPM users load a theme. That static file used to ignore the
# theme's @<theme>-* options, so the same config looked different from running
# the theme's .ps1 directly. For every theme with options this test starts two
# isolated servers with the same options:
#   A  loads the theme through `set -g @plugin` (the PPM path)
#   B  runs the theme's .ps1 with run-shell (the direct path)
# and requires the same status bar from both. It also checks that without any
# option the static look stays, and that an option set after the @plugin line
# still counts.
#
# Isolation: a temporary USERPROFILE (psmux keeps its sockets and plugin
# directory there), a private -L namespace per server, PSMUX_*/TMUX scrubbed,
# and only servers this test started are killed.
# =============================================================================
param([string[]]$Themes)
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL: $name >> $detail" -ForegroundColor Red; $script:fail++ }
}

$repo = Split-Path $PSScriptRoot -Parent
$psmuxBin = (Get-Command psmux -ErrorAction Stop).Source
foreach ($v in 'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE') {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('psmux-theme-opts-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pluginDir = Join-Path $sandbox '.psmux\plugins'
New-Item -ItemType Directory -Force $pluginDir | Out-Null
$oldProfile = $env:USERPROFILE; $oldHome = $env:HOME
$env:USERPROFILE = $sandbox; $env:HOME = $sandbox

$keys = 'status-left', 'status-right', 'status-left-length', 'status-right-length',
        'status-style', 'window-status-format', 'window-status-current-format'
$started = [Collections.Generic.List[string]]::new()

function Read-Bar([string]$sock) {
    ($keys | ForEach-Object { "$_=" + ((& $psmuxBin -L $sock show-options -g -v $_ 2>&1 | Out-String).Trim()) }) -join "`n"
}

function Start-Themed([string]$sock, [string]$conf) {
    $file = Join-Path $sandbox "$sock.conf"
    Set-Content $file $conf -Encoding utf8
    $script:started.Add($sock)
    & $psmuxBin -f $file -L $sock new-session -d -s t -c $sandbox 2>&1 | Out-Null
    for ($i = 0; $i -lt 20; $i++) {
        if ((& $psmuxBin -L $sock ls 2>&1 | Out-String) -match '^t:') { return }
        Start-Sleep -Milliseconds 250
    }
}

# Waits until the bar has moved away from $from (if given) and then stopped
# changing, since the theme scripts set their options one call at a time.
function Wait-Bar([string]$sock, [string]$from, [int]$timeoutSec = 40) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    $last = $null; $stable = 0
    while ((Get-Date) -lt $deadline) {
        $now = Read-Bar $sock
        if ($from -and $now -eq $from) { Start-Sleep -Milliseconds 500; continue }
        if ($now -eq $last) { if (++$stable -ge 3) { return $now } } else { $stable = 0 }
        $last = $now
        Start-Sleep -Milliseconds 700
    }
    return (Read-Bar $sock)
}

function Stop-Themed([string]$sock) {
    & $psmuxBin -L $sock kill-server 2>&1 | Out-Null
}

try {
    $all = Get-ChildItem $repo -Directory -Filter 'psmux-theme-*' | Where-Object {
        (Select-String -Path (Join-Path $_.FullName "$($_.Name).ps1") -Pattern "Get-Opt '@" -Quiet)
    }
    if ($Themes) { $all = $all | Where-Object { $Themes -contains $_.Name } }
    foreach ($t in $all) {
        cmd /c mklink /J (Join-Path $pluginDir $t.Name) $t.FullName | Out-Null
    }

    $pid8 = $PID % 100000
    foreach ($t in $all) {
        $name = $t.Name
        $opt = '@' + ($name -replace '^psmux-theme-', '')
        Write-Host "`n--- $name ---" -ForegroundColor Yellow
        $options = "set -g $opt-show-user 'off'"
        if ($name -eq 'psmux-theme-nord') { $options += "`nset -g @nord-separator 'rounded'" }
        $ps1 = (Join-Path $t.FullName "$name.ps1") -replace '\\', '/'

        $sockA = "thm-a-$pid8-$($name -replace '^psmux-theme-','')"
        $sockB = "thm-b-$pid8-$($name -replace '^psmux-theme-','')"
        Start-Themed $sockA "$options`nset -g @plugin 'psmux-plugins/$name'"
        Start-Themed $sockB "$options`nrun-shell 'pwsh -NoProfile -File `"$ps1`"'"
        $staticLook = Read-Bar $sockA
        $default = Read-Bar $sockB
        $viaPlugin = Wait-Bar $sockA $staticLook
        $viaScript = Wait-Bar $sockB $default
        Check "$name : running the .ps1 directly applies the theme (sanity)" ($viaScript -ne $default -and $viaScript -match 'status-left=\S') $viaScript
        Check "$name : options change the look when loaded with @plugin" ($viaPlugin -ne $staticLook) "still the static plugin.conf look"
        Check "$name : @plugin and the .ps1 give the same status bar" ($viaPlugin -eq $viaScript) "`n@plugin:`n$viaPlugin`n.ps1:`n$viaScript"
        Stop-Themed $sockA; Stop-Themed $sockB
    }

    if (-not $Themes -or $Themes -contains 'psmux-theme-nord') {
        Write-Host "`n--- psmux-theme-nord: no options, option after @plugin ---" -ForegroundColor Yellow
        $sockC = "thm-c-$pid8"
        Start-Themed $sockC "set -g @plugin 'psmux-plugins/psmux-theme-nord'"
        $static = Read-Bar $sockC
        Check "nord: plugin.conf applies its look at once" ($static -match 'status-left-length=30') $static
        Start-Sleep -Seconds 8
        Check "nord: without options the static look stays" ((Read-Bar $sockC) -eq $static) (Read-Bar $sockC)
        Stop-Themed $sockC

        $sockD = "thm-d-$pid8"
        Start-Themed $sockD "set -g @plugin 'psmux-plugins/psmux-theme-nord'`nset -g @nord-show-user 'off'"
        $static = Read-Bar $sockD
        $after = Wait-Bar $sockD $static
        Check "nord: an option set after the @plugin line still applies" ($after -match 'status-left-length=45' -and $after -notmatch '#\{user\}') $after
        Stop-Themed $sockD
    }
}
finally {
    foreach ($s in $started) { Stop-Themed $s }
    $env:USERPROFILE = $oldProfile; $env:HOME = $oldHome
    Get-ChildItem $pluginDir -ErrorAction SilentlyContinue | ForEach-Object { cmd /c rmdir $_.FullName 2>$null }
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nRESULTS: $pass PASS, $fail FAIL"
if ($fail) { exit 1 }
