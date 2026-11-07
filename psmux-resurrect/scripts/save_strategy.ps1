#!/usr/bin/env pwsh
# psmux-resurrect: Save-command strategy resolution.
# See README.md's Save-Command Strategies section for the script contract.

function Get-SaveCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $PaneCommand,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $PanePid,
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $PsmuxBin,
        [Parameter(Mandatory)] [string] $PluginDir,
        [string] $UserStrategiesDir = (Join-Path $env:USERPROFILE '.psmux\strategies\save_command_strategies')
    )

    $strategyName = ''
    try {
        $raw = (& $PsmuxBin show-options -gv '@resurrect-save-command-strategy' 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $strategyName = $raw
        }
    } catch {}
    # Unset (or blank) strategy => record the bare command, no spawn.
    if ([string]::IsNullOrWhiteSpace($strategyName)) { return $PaneCommand }

    $pluginStrategies = Join-Path $PluginDir 'strategies\save_command_strategies'
    $candidates = @(
        (Join-Path $UserStrategiesDir ('{0}.ps1' -f $strategyName)),
        (Join-Path $pluginStrategies  ('{0}.ps1' -f $strategyName))
    )
    $strategyFile = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $strategyFile) { return $PaneCommand }

    # Quoted PowerShell literals preserve leading hyphens as positional values.
    $arguments = @($strategyFile, $PaneCommand, $PanePid, $Directory) | ForEach-Object {
        "'{0}'" -f [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($_)
    }
    $invocation = '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); & ' + ($arguments -join ' ')
    $process = [System.Diagnostics.Process]::new()
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command pwsh -CommandType Application -ErrorAction Stop).Source
        foreach ($argument in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $invocation)) {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        # Native PowerShell output can otherwise replace Unicode with best-fit
        # characters from the host's console code page. Keep both ends UTF-8.
        $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $process.StartInfo = $startInfo
        [void] $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $null = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { return $PaneCommand }
    } catch {
        return $PaneCommand
    } finally {
        $process.Dispose()
    }

    $resolved = ($stdout -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($resolved)) { return $PaneCommand }
    return $resolved.Trim()
}
