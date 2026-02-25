#!/usr/bin/env pwsh
# PPM - Remove plugins not declared in config
$ErrorActionPreference = 'Continue'
$PPM_ROOT = Split-Path -Parent $PSScriptRoot
. "$PPM_ROOT\ppm.ps1"
Remove-UnusedPlugins
