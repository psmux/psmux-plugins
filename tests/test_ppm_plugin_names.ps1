#!/usr/bin/env pwsh
# Plugin loading, update lookup and cleanup must use the installer's resolved name.
# Host-safe: isolated directories, fake psmux, no git or live server calls.
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check($name, $condition) {
    if ($condition) { Write-Host "PASS: $name"; $script:pass++ }
    else { Write-Host "FAIL: $name"; $script:fail++ }
}

$ppm = Join-Path (Split-Path $PSScriptRoot -Parent) 'ppm/ppm.ps1'
$source = Get-Content $ppm -Raw
$marker = $source.IndexOf('# ENTRY POINT')
if ($marker -lt 0) { throw 'PPM entry-point marker missing.' }
$errors = $null; $tokens = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'PPM parse failed.' }
# Load functions without running PPM initialization against the user's server.
foreach ($node in $ast.EndBlock.Statements) {
    if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) {
        Invoke-Expression $node.Extent.Text
    }
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('ppm-names-' + [guid]::NewGuid().ToString('N'))
$script:PLUGIN_DIR = Join-Path $sandbox 'plugins'
$script:MONOREPO_MAP = @{ 'psmux-plugins' = 'psmux/psmux-plugins' }
$script:PROGRESS_TOAST_MS = 60000
$oldProfile = $env:USERPROFILE
try {
    New-Item -ItemType Directory $script:PLUGIN_DIR -Force | Out-Null
    $env:USERPROFILE = $sandbox
    $script:PSMUX = Join-Path $sandbox 'psmux.ps1'
    # Get-DeclaredPlugins runs normally; this fake returns no option declarations,
    # leaving the sandbox config as the declaration source.
    'exit 0' | Set-Content $script:PSMUX
    function Register-PPMBindings {}
    function Show-PpmStatus($Message) { $script:statuses += $Message }
    function Clear-PpmStatus {}
    function Remove-PluginActivation($PluginName) {}
    function Initialize-Plugin($PluginPath) { $script:loaded += Split-Path $PluginPath -Leaf }
    function Update-Plugin($PluginPath, $Spec) { $script:updated[ (Split-Path $PluginPath -Leaf) ] = $Spec }
    function Install-Plugin($Spec) { $script:installed += $Spec; return $true }

    foreach ($suffix in '', '#main', '#temp/integration') {
        $script:specs = @(
            "psmux-plugins/psmux-sensible$suffix",
            "MattKotsenas/psmux-plugins/psmux-resurrect$suffix",
            "psmux-continuum$suffix"
        )
        ($specs | ForEach-Object { "set -g @plugin '$_'" }) | Set-Content (Join-Path $sandbox '.psmux.conf')
        foreach ($name in 'ppm', 'psmux-sensible', 'psmux-resurrect', 'psmux-continuum', 'unused') {
            New-Item -ItemType Directory (Join-Path $PLUGIN_DIR $name) -Force | Out-Null
        }
        $declared = @(Get-DeclaredPlugins)
        Check "fixture declarations ($suffix)" (($declared -join '|') -eq ($specs -join '|'))
        Check "installer resolves resurrect ($suffix)" ((Resolve-PluginSpec $specs[1]).Name -eq 'psmux-resurrect')

        $script:loaded = @()
        Invoke-Expression $source.Substring($marker)
        Check "startup loads all declared plugins ($suffix)" (($loaded | Sort-Object) -join '|' -eq 'psmux-continuum|psmux-resurrect|psmux-sensible')

        $script:installed = @()
        $script:statuses = @()
        Install-AllPlugins
        Check "install preserves full specs ($suffix)" (($installed -join '|') -eq ($specs -join '|'))
        foreach ($spec in $specs) {
            $name = (Resolve-PluginSpec $spec).Name
            Check "install displays resolved name for $name ($suffix)" ($statuses -contains "PPM: Installing $name...")
        }

        $script:updated = @{}
        Update-AllPlugins
        foreach ($spec in $specs) {
            $name = (Resolve-PluginSpec $spec).Name
            Check "update retains spec for $name ($suffix)" ($updated[$name] -eq $spec)
        }

        Check "cleanup fixture contains declared and unused plugins ($suffix)" ((Test-Path (Join-Path $PLUGIN_DIR 'psmux-resurrect')) -and (Test-Path (Join-Path $PLUGIN_DIR 'unused')))
        Remove-UnusedPlugins
        Check "cleanup keeps exactly declared plugins and ppm ($suffix)" (((Get-ChildItem $PLUGIN_DIR -Directory).Name | Sort-Object) -join '|' -eq 'ppm|psmux-continuum|psmux-resurrect|psmux-sensible')
    }
} finally {
    $env:USERPROFILE = $oldProfile
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "RESULTS: $pass PASS, $fail FAIL"
if ($fail) { exit 1 }
