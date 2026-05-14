#!/usr/bin/env pwsh
# psmux-resurrect: Strategy resolution for restoring program state
#
# Port of tmux-resurrect's per-program strategy mechanism. At restore time,
# instead of replaying the saved command verbatim, this looks up an optional
# strategy script that can compute a more useful restore command (e.g., for
# tools that maintain their own session IDs, log files, or workspace state).
#
# Activation (in psmux.conf):
#   set -g @resurrect-strategy-<program> '<strategy-name>'
#
# Lookup order (first match wins):
#   1. ~/.psmux/strategies/<program>_<strategy>.ps1   (user dir; can override)
#   2. <plugin>/strategies/<program>_<strategy>.ps1   (bundled fallback)
#
# Strategy contract:
#   Invoked as: pwsh -NoProfile -File <strategy>.ps1 <originalCommand> <directory>
#   Writes one line to stdout: the command to send to the pane.
#   Should echo the original command if it cannot improve on it.

function Get-StrategyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $OriginalCommand,
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $PsmuxBin,
        [Parameter(Mandatory)] [string] $PluginDir,
        [string] $UserStrategiesDir = (Join-Path $env:USERPROFILE '.psmux\strategies')
    )

    if ([string]::IsNullOrWhiteSpace($OriginalCommand)) { return $OriginalCommand }

    $program = ($OriginalCommand -split '\s+', 2)[0]
    $program = ($program -split '[\\/]' | Select-Object -Last 1) -replace '\.exe$', ''
    if ([string]::IsNullOrWhiteSpace($program)) { return $OriginalCommand }

    $strategyName = ''
    try {
        $raw = (& $PsmuxBin show-options -gv "@resurrect-strategy-$program" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $raw -and
            $raw -notmatch 'unknown option|error|no server|not found|refused') {
            $strategyName = $raw
        }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($strategyName)) { return $OriginalCommand }

    $pluginStrategies = Join-Path $PluginDir 'strategies'
    $candidates = @(
        (Join-Path $UserStrategiesDir  "${program}_${strategyName}.ps1"),
        (Join-Path $pluginStrategies   "${program}_${strategyName}.ps1")
    )
    $strategyFile = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $strategyFile) { return $OriginalCommand }

    $stdout = $null
    try {
        $stdout = & pwsh -NoProfile -ExecutionPolicy Bypass -File $strategyFile $OriginalCommand $Directory 2>$null
    } catch {
        return $OriginalCommand
    }
    if ($null -eq $stdout) { return $OriginalCommand }

    $resolved = (($stdout -join "`n") -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($resolved)) { return $OriginalCommand }
    return $resolved.Trim()
}
