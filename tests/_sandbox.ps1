# =============================================================================
# Shared test sandbox. Dot-source it at the top of a test:
#
#   . (Join-Path $PSScriptRoot '_sandbox.ps1')
#   try { ...test... } finally { Exit-TestSandbox }
#
# psmux keeps its sockets, config and plugins under USERPROFILE, so pointing
# USERPROFILE at a temporary home gives the test its own default server, its
# own ~/.psmux.conf and its own ~/.psmux/resurrect. Nothing the test starts,
# writes or kills can reach the user's real sessions or snapshots.
# ~/.psmux/plugins links every plugin in this checkout, so tests exercise the
# code under review rather than whatever is installed.
# =============================================================================

$script:SandboxSaved = @{}
foreach ($v in 'USERPROFILE', 'HOME', 'PSMUX_DATA_DIR', 'PSMUX_ALLOW_NESTING') {
    $script:SandboxSaved[$v] = [Environment]::GetEnvironmentVariable($v)
}
foreach ($v in 'PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_TARGET_SESSION', 'TMUX', 'TMUX_PANE') {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}

$script:SandboxRoot = Join-Path ([IO.Path]::GetTempPath()) ('psmux-plugins-test-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
$script:SandboxHome = Join-Path $script:SandboxRoot 'home'
$sandboxPlugins = Join-Path $script:SandboxHome '.psmux\plugins'
foreach ($d in $sandboxPlugins, (Join-Path $script:SandboxHome '.psmux\resurrect'), (Join-Path $script:SandboxRoot 'data'),
               (Join-Path $script:SandboxHome 'Documents\workspace'), (Join-Path $script:SandboxHome 'Desktop')) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}
$repoRoot = Split-Path $PSScriptRoot -Parent
Get-ChildItem $repoRoot -Directory | Where-Object { $_.Name -like 'psmux-*' -or $_.Name -eq 'ppm' } | ForEach-Object {
    New-Item -ItemType Junction -Path (Join-Path $sandboxPlugins $_.Name) -Target $_.FullName | Out-Null
}

$env:USERPROFILE = $script:SandboxHome
$env:HOME = $script:SandboxHome
$env:PSMUX_DATA_DIR = Join-Path $script:SandboxRoot 'data'
$env:PSMUX_ALLOW_NESTING = '1'

function Exit-TestSandbox {
    $bin = Get-Command psmux -ErrorAction SilentlyContinue
    # Kills the sandbox's own default server only: USERPROFILE still points
    # at the sandbox here.
    if ($bin -and $env:USERPROFILE -eq $script:SandboxHome) { & $bin.Source kill-server 2>&1 | Out-Null }
    foreach ($v in $script:SandboxSaved.Keys) {
        [Environment]::SetEnvironmentVariable($v, $script:SandboxSaved[$v])
    }
    # Remove the junctions first so deleting the sandbox can never follow
    # them into the checkout.
    Get-ChildItem (Join-Path $script:SandboxHome '.psmux\plugins') -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType -eq 'Junction' } | ForEach-Object { $_.Delete() }
    Remove-Item $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
}
