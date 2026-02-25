#!/usr/bin/env pwsh
# =============================================================================
# PPM - Psmux Plugin Manager
# The plugin manager for psmux (like tpm for tmux)
# https://github.com/psmux-plugins/ppm
# =============================================================================
#
# Usage in ~/.psmux.conf:
#   set -g @plugin 'psmux-plugins/ppm'
#   set -g @plugin 'psmux-plugins/psmux-sensible'
#   set -g @plugin 'psmux-plugins/psmux-yank'
#   run '~/.psmux/plugins/ppm/ppm.ps1'
#
# Key bindings (after loading):
#   Prefix + I    - Install plugins
#   Prefix + U    - Update plugins
#   Prefix + M    - Remove/clean unused plugins
# =============================================================================

$ErrorActionPreference = 'Continue'

# --- Resolve paths ---
$PPM_ROOT = $PSScriptRoot
$PLUGIN_DIR = Split-Path -Parent $PPM_ROOT
$PSMUX_HOME = Split-Path -Parent $PLUGIN_DIR

# Detect the psmux binary (psmux, pmux, or tmux)
function Get-PsmuxBinary {
    foreach ($name in @('psmux', 'pmux', 'tmux')) {
        $bin = Get-Command $name -ErrorAction SilentlyContinue
        if ($bin) { return $bin.Source }
    }
    # Fallback: check common install locations
    foreach ($name in @('psmux.exe', 'pmux.exe', 'tmux.exe')) {
        $paths = @(
            "$env:LOCALAPPDATA\psmux\$name",
            "$env:USERPROFILE\.cargo\bin\$name",
            "$env:ProgramFiles\psmux\$name"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) { return $p }
        }
    }
    return 'psmux'
}

$script:PSMUX = Get-PsmuxBinary

function Invoke-Psmux {
    param([Parameter(ValueFromRemainingArguments)]$Args)
    & $script:PSMUX @Args 2>&1
}

# --- Parse @plugin declarations from psmux options ---
function Get-DeclaredPlugins {
    param([string]$SessionTarget)
    $plugins = @()

    # Method 1: Query show-options for @plugin values
    $opts = if ($SessionTarget) {
        Invoke-Psmux show-options -t $SessionTarget -g 2>&1
    } else {
        Invoke-Psmux show-options -g 2>&1
    }

    $optsText = ($opts | Out-String)
    # Match lines like: @plugin "psmux-plugins/psmux-sensible"
    $matches = [regex]::Matches($optsText, '@plugin\s+[''"]?([^''"]+)[''"]?')
    foreach ($m in $matches) {
        $val = $m.Groups[1].Value.Trim()
        if ($val -and $val -ne 'psmux-plugins/ppm') {
            $plugins += $val
        }
    }

    # Method 2: Also scan config files for @plugin declarations
    $configPaths = @(
        "$env:USERPROFILE\.psmux.conf",
        "$env:USERPROFILE\.psmuxrc",
        "$env:USERPROFILE\.tmux.conf",
        "$env:USERPROFILE\.config\psmux\psmux.conf"
    )
    foreach ($cfg in $configPaths) {
        if (Test-Path $cfg) {
            $content = Get-Content $cfg -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $cfgMatches = [regex]::Matches($content, "set\s+-g\s+@plugin\s+['""]([^'""]+)['""]")
                foreach ($m in $cfgMatches) {
                    $val = $m.Groups[1].Value.Trim()
                    if ($val -and $val -ne 'psmux-plugins/ppm' -and $val -notin $plugins) {
                        $plugins += $val
                    }
                }
            }
            break  # Only read the first found config file (psmux behavior)
        }
    }

    return $plugins
}

# --- Resolve plugin spec to git URL and local path ---
function Resolve-PluginSpec {
    param([string]$Spec)
    $name = $Spec.Split('/')[-1]
    $localPath = Join-Path $PLUGIN_DIR $name

    if ($Spec -match '^https?://') {
        # Full URL
        return @{ Name = $name; Url = $Spec; Path = $localPath }
    }
    elseif ($Spec -match '^[^/]+/[^/]+$') {
        # GitHub short form: owner/repo
        return @{ Name = $name; Url = "https://github.com/$Spec.git"; Path = $localPath }
    }
    else {
        # Just a name, assume psmux-plugins org
        return @{ Name = $Spec; Url = "https://github.com/psmux-plugins/$Spec.git"; Path = $localPath }
    }
}

# --- Install a single plugin ---
function Install-Plugin {
    param([string]$Spec)
    $info = Resolve-PluginSpec $Spec

    if (Test-Path $info.Path) {
        Write-Host "  Already installed: $($info.Name)" -ForegroundColor DarkGray
        return $true
    }

    Write-Host "  Installing: $($info.Name) ..." -ForegroundColor Cyan
    try {
        git clone --depth 1 $info.Url $info.Path 2>&1 | Out-Null
        if (Test-Path $info.Path) {
            Write-Host "  Installed: $($info.Name)" -ForegroundColor Green
            # Source the plugin
            Initialize-Plugin $info.Path
            return $true
        }
    } catch {}

    # If git clone fails, check if it's a local/bundled plugin
    $bundledPath = Join-Path $PPM_ROOT "bundled\$($info.Name)"
    if (Test-Path $bundledPath) {
        Copy-Item -Path $bundledPath -Destination $info.Path -Recurse -Force
        Write-Host "  Installed (bundled): $($info.Name)" -ForegroundColor Green
        Initialize-Plugin $info.Path
        return $true
    }

    Write-Host "  FAILED: $($info.Name) - could not clone from $($info.Url)" -ForegroundColor Red
    return $false
}

# --- Update a single plugin ---
function Update-Plugin {
    param([string]$PluginPath)
    $name = Split-Path -Leaf $PluginPath
    if (-not (Test-Path (Join-Path $PluginPath '.git'))) {
        Write-Host "  Skip (not git): $name" -ForegroundColor DarkGray
        return
    }
    Write-Host "  Updating: $name ..." -ForegroundColor Cyan
    Push-Location $PluginPath
    try {
        git pull --rebase 2>&1 | Out-Null
        Write-Host "  Updated: $name" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED: $name" -ForegroundColor Red
    }
    Pop-Location
}

# --- Initialize/source a plugin ---
function Initialize-Plugin {
    param([string]$PluginPath)
    $name = Split-Path -Leaf $PluginPath

    # Look for the main plugin entry point (in priority order)
    $entryPoints = @(
        (Join-Path $PluginPath "$name.ps1"),
        (Join-Path $PluginPath "$($name -replace '^psmux-','').ps1"),
        (Join-Path $PluginPath 'plugin.ps1'),
        (Join-Path $PluginPath 'init.ps1')
    )

    foreach ($ep in $entryPoints) {
        if (Test-Path $ep) {
            try {
                & $ep
            } catch {
                Write-Host "  Warning: Error sourcing $name : $_" -ForegroundColor Yellow
            }
            return
        }
    }

    # Fallback: look for .conf files to source
    $confFiles = Get-ChildItem -Path $PluginPath -Filter '*.conf' -File -ErrorAction SilentlyContinue
    foreach ($cf in $confFiles) {
        Invoke-Psmux source-file $cf.FullName 2>&1 | Out-Null
    }
}

# --- Main: Install all plugins ---
function Install-AllPlugins {
    $plugins = Get-DeclaredPlugins
    if ($plugins.Count -eq 0) {
        Write-Host "PPM: No plugins declared. Add 'set -g @plugin ""owner/repo""' to your config." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "PPM - Installing plugins..." -ForegroundColor Magenta
    Write-Host ("=" * 50) -ForegroundColor Magenta

    $installed = 0
    foreach ($spec in $plugins) {
        if (Install-Plugin $spec) { $installed++ }
    }

    Write-Host ("=" * 50) -ForegroundColor Magenta
    Write-Host "PPM: $installed/$($plugins.Count) plugins installed." -ForegroundColor Magenta
    Write-Host ""
}

# --- Main: Update all plugins ---
function Update-AllPlugins {
    Write-Host ""
    Write-Host "PPM - Updating plugins..." -ForegroundColor Magenta
    Write-Host ("=" * 50) -ForegroundColor Magenta

    $dirs = Get-ChildItem -Path $PLUGIN_DIR -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'ppm' }

    if ($dirs.Count -eq 0) {
        Write-Host "  No plugins to update." -ForegroundColor DarkGray
        return
    }

    foreach ($dir in $dirs) {
        Update-Plugin $dir.FullName
    }

    Write-Host ("=" * 50) -ForegroundColor Magenta
    Write-Host "PPM: Update complete." -ForegroundColor Magenta
    Write-Host ""
}

# --- Main: Clean unused plugins ---
function Remove-UnusedPlugins {
    $plugins = Get-DeclaredPlugins
    $declaredNames = $plugins | ForEach-Object { ($_ -split '/')[-1] }

    Write-Host ""
    Write-Host "PPM - Cleaning unused plugins..." -ForegroundColor Magenta
    Write-Host ("=" * 50) -ForegroundColor Magenta

    $dirs = Get-ChildItem -Path $PLUGIN_DIR -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'ppm' }

    $removed = 0
    foreach ($dir in $dirs) {
        if ($dir.Name -notin $declaredNames) {
            Write-Host "  Removing: $($dir.Name)" -ForegroundColor Yellow
            Remove-Item -Recurse -Force $dir.FullName -ErrorAction SilentlyContinue
            $removed++
        }
    }

    if ($removed -eq 0) {
        Write-Host "  All plugins are in use." -ForegroundColor Green
    } else {
        Write-Host "  Removed $removed unused plugin(s)." -ForegroundColor Yellow
    }

    Write-Host ("=" * 50) -ForegroundColor Magenta
    Write-Host ""
}

# --- Register PPM keybindings ---
function Register-PPMBindings {
    # Convert to forward slashes to avoid psmux backslash stripping
    $ppmFwd = $PPM_ROOT -replace '\\', '/'
    $installPath = "$ppmFwd/scripts/install_plugins.ps1"
    $updatePath  = "$ppmFwd/scripts/update_plugins.ps1"
    $cleanPath   = "$ppmFwd/scripts/clean_plugins.ps1"

    Invoke-Psmux bind-key I "run-shell 'pwsh -NoProfile -File `"$installPath`"'" 2>&1 | Out-Null
    Invoke-Psmux bind-key U "run-shell 'pwsh -NoProfile -File `"$updatePath`"'" 2>&1 | Out-Null
    Invoke-Psmux bind-key M "run-shell 'pwsh -NoProfile -File `"$cleanPath`"'" 2>&1 | Out-Null
}

# =============================================================================
# ENTRY POINT
# =============================================================================
# When sourced via `run` in .psmux.conf, this:
# 1. Ensures the plugin directory exists
# 2. Registers PPM key bindings
# 3. Sources all installed plugins
# 4. Does NOT auto-install (user presses Prefix+I for that)

# Ensure plugin directory exists
if (-not (Test-Path $PLUGIN_DIR)) {
    New-Item -ItemType Directory -Path $PLUGIN_DIR -Force | Out-Null
}

# Register PPM key bindings
Register-PPMBindings

# Source only plugins that are declared in config (not every directory)
$declaredPlugins = Get-DeclaredPlugins
$declaredNames = $declaredPlugins | ForEach-Object { ($_ -split '/')[-1] }

$installedPlugins = Get-ChildItem -Path $PLUGIN_DIR -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne 'ppm' -and $_.Name -in $declaredNames }

foreach ($pluginDir in $installedPlugins) {
    Initialize-Plugin $pluginDir.FullName
}

Write-Host "PPM: Loaded $($installedPlugins.Count) plugin(s). Press Prefix+I to install new plugins." -ForegroundColor DarkGray
