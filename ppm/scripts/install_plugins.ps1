#!/usr/bin/env pwsh
# PPM - Install all declared plugins
$ErrorActionPreference = 'Continue'
$PPM_ROOT = Split-Path -Parent $PSScriptRoot
. "$PPM_ROOT\ppm.ps1"
Install-AllPlugins
