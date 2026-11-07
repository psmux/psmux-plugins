#!/usr/bin/env pwsh
# Reference save-command strategy: writes the original command to stdout.
# See README.md's Save-Command Strategies section for the script contract.
param(
    [Parameter(Position = 0)] [AllowEmptyString()] [string] $Command,
    [Parameter(Position = 1)] [AllowEmptyString()] [string] $PanePid,
    [Parameter(Position = 2)] [AllowEmptyString()] [string] $Directory
)

Write-Output $Command
