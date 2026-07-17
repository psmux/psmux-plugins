#!/usr/bin/env pwsh
# =============================================================================
# ppm.ps1 Spec Resolution Test
# Tests plugin-spec parsing/resolution behavior added for #16 and #25:
#   - #branch suffix splitting (applies to every spec shape)
#   - 3-segment owner/repo/subdir routing (no probe, no MONOREPO_MAP)
#   - Backward-compatible 2-segment and bare-name resolution, including the
#     MapFirst monorepo short-circuit added for #25
#   - URL passthrough (https and git@ SSH forms)
# Plus one real sandboxed install using the 3-segment + #branch form against
# a public fork, proving the resolution logic actually drives a working git
# clone end-to-end (and that --branch is genuinely enforced, not ignored).
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
$results = @()

function Check($name, $cond, $detail = '') {
    if ($cond) {
        Write-Host "  PASS: $name" -ForegroundColor Green
        $script:pass++
        $script:results += [PSCustomObject]@{ Test = $name; Result = 'PASS'; Detail = $detail }
    } else {
        Write-Host "  FAIL: $name $(if($detail){' >> ' + $detail})" -ForegroundColor Red
        $script:fail++
        $script:results += [PSCustomObject]@{ Test = $name; Result = 'FAIL'; Detail = $detail }
    }
}

Write-Host "`n=== ppm.ps1 Spec Resolution Test (#16 / #25) ===" -ForegroundColor Magenta

# =============================================================================
# Load ppm.ps1's functions without running its entry point. The entry point
# registers key bindings against the live psmux server and sources installed
# plugins - neither of which a spec-resolution test should ever trigger.
# =============================================================================
$PPM_SCRIPT = Join-Path (Split-Path $PSScriptRoot -Parent) 'ppm\ppm.ps1'
Check "ppm.ps1 exists" (Test-Path $PPM_SCRIPT) $PPM_SCRIPT

$ppmSource = Get-Content $PPM_SCRIPT -Raw
$entryPointMarker = "# ENTRY POINT"
$idx = $ppmSource.IndexOf($entryPointMarker)
Check "ppm.ps1 has an ENTRY POINT marker to slice on" ($idx -ge 0)

$functionsOnly = if ($idx -ge 0) { $ppmSource.Substring(0, $idx) } else { $ppmSource }
$tmpFuncFile = Join-Path ([System.IO.Path]::GetTempPath()) "ppm-functions-$(Get-Random).ps1"
$functionsOnly | Set-Content -Path $tmpFuncFile -Encoding UTF8

try {
    . $tmpFuncFile
    Check "ppm.ps1 functions load without error" $true
} catch {
    Check "ppm.ps1 functions load without error" $false $_.Exception.Message
}
Check "Resolve-PluginSpec is defined after load" ([bool](Get-Command Resolve-PluginSpec -ErrorAction SilentlyContinue))
Check "Install-Plugin is defined after load" ([bool](Get-Command Install-Plugin -ErrorAction SilentlyContinue))

# =============================================================================
# PHASE 1: Resolve-PluginSpec resolution-table unit tests
# =============================================================================
Write-Host "`n--- Phase 1: Spec Resolution Unit Tests ---" -ForegroundColor Yellow

# Isolate PLUGIN_DIR for these pure-parsing checks (Resolve-PluginSpec only
# builds a path string, it never touches disk).
$script:PLUGIN_DIR = Join-Path ([System.IO.Path]::GetTempPath()) "ppm-spec-test-plugins"

function CheckSpec {
    param($Spec, $Label, $ExpName, $ExpUrl, $ExpOrg, $ExpMapFirst, $ExpMonorepo, $ExpBranch)
    $r = Resolve-PluginSpec $Spec
    $ok = ($r.Name -eq $ExpName) -and ($r.Url -eq $ExpUrl) -and ($r.Org -eq $ExpOrg) `
          -and ($r.MapFirst -eq $ExpMapFirst) -and ($r.Monorepo -eq $ExpMonorepo) -and ($r.Branch -eq $ExpBranch)
    $detail = "spec='$Spec' -> Name=$($r.Name) Url=$($r.Url) Org=$($r.Org) MapFirst=$($r.MapFirst) Monorepo=$($r.Monorepo) Branch=$($r.Branch)"
    Check $Label $ok $detail
}

# Backward compat: bare name -> psmux-plugins alias
CheckSpec 'psmux-sensible' 'bare name resolves to psmux-plugins alias, map-first' `
    'psmux-sensible' 'https://github.com/psmux-plugins/psmux-sensible.git' 'psmux-plugins' $true $null $null

# Backward compat: 2-segment, known monorepo owner -> map-first (added for #25,
# raised in #16 as the sane follow-up; no behavior regression for #16 itself)
CheckSpec 'psmux-plugins/psmux-continuum' '2-segment known-owner resolves map-first (no probe)' `
    'psmux-continuum' 'https://github.com/psmux-plugins/psmux-continuum.git' 'psmux-plugins' $true $null $null

# Backward compat: 2-segment, unknown owner -> probe-first (unchanged)
CheckSpec 'someorg/someplugin' '2-segment unknown-owner resolves probe-first' `
    'someplugin' 'https://github.com/someorg/someplugin.git' 'someorg' $false $null $null

# URL passthrough: https
CheckSpec 'https://github.com/foo/bar.git' 'https URL passes through unchanged' `
    'bar.git' 'https://github.com/foo/bar.git' $null $false $null $null

# URL passthrough: git@ SSH form
CheckSpec 'git@github.com:foo/bar.git' 'git@ SSH URL passes through unchanged' `
    'bar.git' 'git@github.com:foo/bar.git' $null $false $null $null

# NEW (#16): 3-segment owner/repo/subdir - no probe, no MONOREPO_MAP
CheckSpec 'MattKotsenas/psmux-plugins/psmux-continuum' '3-segment owner/repo/subdir routes to explicit monorepo' `
    'psmux-continuum' 'https://github.com/MattKotsenas/psmux-plugins.git' 'MattKotsenas' $true 'MattKotsenas/psmux-plugins' $null

# NEW (#16): #branch suffix on a 2-segment spec
CheckSpec 'MattKotsenas/psmux-continuum#fix-branch' '#branch suffix splits off a 2-segment spec' `
    'psmux-continuum' 'https://github.com/MattKotsenas/psmux-continuum.git' 'MattKotsenas' $false $null 'fix-branch'

# NEW (#16): #branch combined with 3-segment (the issue's motivating example)
CheckSpec 'MattKotsenas/psmux-plugins/psmux-continuum#fix-branch' '#branch + 3-segment combine (issue motivating example)' `
    'psmux-continuum' 'https://github.com/MattKotsenas/psmux-plugins.git' 'MattKotsenas' $true 'MattKotsenas/psmux-plugins' 'fix-branch'

# NEW (#16): #branch on a bare name
CheckSpec 'psmux-sensible#main' '#branch suffix splits off a bare name' `
    'psmux-sensible' 'https://github.com/psmux-plugins/psmux-sensible.git' 'psmux-plugins' $true $null 'main'

# NEW (#16): #branch on a URL
CheckSpec 'https://github.com/foo/bar.git#dev' '#branch suffix splits off a URL passthrough spec' `
    'bar.git' 'https://github.com/foo/bar.git' $null $false $null 'dev'

# =============================================================================
# PHASE 2: Real sandboxed install using the 3-segment + #branch form
# =============================================================================
Write-Host "`n--- Phase 2: Real Sandboxed Install (3-segment + #branch) ---" -ForegroundColor Yellow

# House rule: NEVER touch the real user's plugin dir or psmux config. Redirect
# USERPROFILE (what ppm.ps1 uses to locate .psmux.conf and, by extension, the
# plugin dir) to a throwaway sandbox for the duration of this phase only.
$origUserProfile = $env:USERPROFILE
$sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ppm-install-test-$(Get-Random)"
$sandboxHome = Join-Path $sandboxRoot 'home'
$sandboxPlugins = Join-Path $sandboxRoot 'plugins'
New-Item -ItemType Directory -Path $sandboxHome, $sandboxPlugins -Force | Out-Null

try {
    $env:USERPROFILE = $sandboxHome
    $script:PLUGIN_DIR = $sandboxPlugins

    $spec = 'MattKotsenas/psmux-plugins/psmux-continuum#feat/ppm-branch-and-subdir-syntax'
    $ok = Install-Plugin $spec
    Check "Install-Plugin succeeds for 3-segment + #branch spec against a real fork" $ok $spec

    $installedPath = Join-Path $sandboxPlugins 'psmux-continuum'
    Check "installed plugin directory exists" (Test-Path $installedPath) $installedPath
    Check "installed plugin.conf exists" (Test-Path (Join-Path $installedPath 'plugin.conf'))

    $markerPath = Join-Path $installedPath '.monorepo.json'
    if (Test-Path $markerPath) {
        $meta = Get-Content $markerPath -Raw | ConvertFrom-Json
        Check ".monorepo.json records the explicit fork monorepo" ($meta.monorepo -eq 'MattKotsenas/psmux-plugins') "got '$($meta.monorepo)'"
        Check ".monorepo.json records the requested branch" ($meta.branch -eq 'feat/ppm-branch-and-subdir-syntax') "got '$($meta.branch)'"
    } else {
        Check ".monorepo.json marker exists" $false $markerPath
    }

    # Negative check: a bogus branch on the same 3-segment spec must fail
    # cleanly, proving --branch is actually enforced (not silently ignored).
    Remove-Item -Recurse -Force $sandboxPlugins -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $sandboxPlugins -Force | Out-Null
    $badSpec = 'MattKotsenas/psmux-plugins/psmux-continuum#this-branch-does-not-exist-zzz'
    $badOk = Install-Plugin $badSpec
    Check "bogus #branch on a 3-segment spec fails cleanly" (-not $badOk) $badSpec
    Check "bogus #branch install leaves no partial directory" (-not (Test-Path (Join-Path $sandboxPlugins 'psmux-continuum')))
} finally {
    $env:USERPROFILE = $origUserProfile
    Remove-Item -Recurse -Force $sandboxRoot -ErrorAction SilentlyContinue
    Remove-Item -Force $tmpFuncFile -ErrorAction SilentlyContinue
}

# =============================================================================
# Summary
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "  RESULTS: $pass PASS, $fail FAIL" -ForegroundColor $(if($fail -gt 0){'Red'}else{'Green'})
Write-Host "========================================" -ForegroundColor Magenta

if ($fail -gt 0) {
    Write-Host "`nFailed tests:" -ForegroundColor Red
    $results | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
        Write-Host "  - $($_.Test)$(if($_.Detail){": $($_.Detail)"})" -ForegroundColor Red
    }
}

Write-Host ""
exit $fail
