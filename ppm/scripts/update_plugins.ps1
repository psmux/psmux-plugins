#!/usr/bin/env pwsh
# PPM - Update all installed plugins
$ErrorActionPreference = 'Continue'
$PPM_ROOT = Split-Path -Parent $PSScriptRoot
. "$PPM_ROOT\ppm.ps1"
Update-AllPlugins
