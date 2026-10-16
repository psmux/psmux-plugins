#!/usr/bin/env pwsh
# Save-command strategy resolution tests. All psmux calls use a fake script;
# strategies and output stay in a temporary directory. No server is required.
$ErrorActionPreference = 'Stop'

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL: $name >> $detail" -ForegroundColor Red; $script:fail++ }
}

$plugin = Join-Path (Split-Path $PSScriptRoot -Parent) 'psmux-resurrect'
. (Join-Path $plugin 'scripts\save_strategy.ps1')
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('save-strategy-' + [guid]::NewGuid().ToString('N'))
$userDir = Join-Path $sandbox 'user'
$bundleDir = Join-Path $sandbox 'plugin\strategies\save_command_strategies'
New-Item -ItemType Directory -Path $userDir, $bundleDir -Force | Out-Null
$fake = Join-Path $sandbox 'psmux.ps1'
$optionFile = Join-Path $sandbox 'option.txt'
$optionExitFile = Join-Path $sandbox 'option-exit.txt'
@"
Get-Content -LiteralPath '$optionFile'
exit ([int](Get-Content -LiteralPath '$optionExitFile'))
"@ | Set-Content $fake

function Set-Option([string]$name, [int]$exitCode = 0) {
    Set-Content $optionFile $name
    Set-Content $optionExitFile $exitCode
}
function Resolve-Command([string]$command = 'pwsh', [string]$panePid = '1234', [string]$directory = "C:\work space\O'Brien") {
    Get-SaveCommand -PaneCommand $command -PanePid $panePid -Directory $directory `
        -PsmuxBin $fake -PluginDir (Join-Path $sandbox 'plugin') -UserStrategiesDir $userDir
}
function Write-Strategy([string]$name, [string]$body) {
    Set-Content (Join-Path $userDir "$name.ps1") $body
}

try {
    # A marker detects accidental invocation when the option is unset.
    $marker = Join-Path $sandbox 'invoked.txt'
    Write-Strategy 'default' "Set-Content '$marker' invoked; Write-Output modified"
    Set-Option ''
    Check 'unset option preserves the command' ((Resolve-Command) -ceq 'pwsh')
    Check 'unset option invokes no strategy' (-not (Test-Path $marker))
    Set-Option 'default' 1
    Check 'failed option query preserves the command' ((Resolve-Command) -ceq 'pwsh')
    Check 'failed option query invokes no strategy' (-not (Test-Path $marker))
    Set-Option 'missing'
    Check 'missing script preserves the command' ((Resolve-Command) -ceq 'pwsh')

    Write-Strategy 'arguments' @'
param([string]$Command, [string]$PanePid, [string]$Directory)
"$Command|$PanePid|$Directory"
'@
    Set-Option 'arguments'
    $actual = Resolve-Command 'tool --resume=abc' '5678'
    Check 'passes command, pane pid and directory unchanged' `
        ($actual -ceq "tool --resume=abc|5678|C:\work space\O'Brien") $actual
    $actual = Resolve-Command '' ''
    Check 'passes empty command and pid' ($actual -ceq "||C:\work space\O'Brien") $actual
    $actual = Resolve-Command '-tool'
    Check 'passes leading-hyphen commands literally' ($actual -ceq "-tool|1234|C:\work space\O'Brien") $actual
    $literal = 'tool --name="O''Brien" $(Write-Output WRONG); & | C:\work\'
    $actual = Resolve-Command $literal
    Check 'passes quotes, shell syntax and trailing backslashes literally' `
        ($actual -ceq "$literal|1234|C:\work space\O'Brien") $actual

    Set-Content (Join-Path $bundleDir 'bundled.ps1') 'Write-Output bundled'
    Set-Option 'bundled'
    Check 'uses bundled strategy when user file is absent' ((Resolve-Command) -ceq 'bundled')
    Write-Strategy 'bundled' 'Write-Output user'
    Check 'user strategy overrides bundled strategy' ((Resolve-Command) -ceq 'user')
    Write-Strategy 'bundled' 'exit 1'
    Check 'failed user strategy falls back to command, not bundled strategy' ((Resolve-Command) -ceq 'pwsh')

    Write-Strategy 'error-handler' 'Write-Output resolved'
    Set-Option 'error-handler'
    Check 'strategy names can contain error-related words' ((Resolve-Command) -ceq 'resolved')

    Write-Strategy 'lines' "Write-Output ''; Write-Output '   '; Write-Output '  tool --resume=abc  '; Write-Output ignored"
    Set-Option 'lines'
    Check 'uses first nonempty stdout line and trims it' ((Resolve-Command) -ceq 'tool --resume=abc')
    Write-Strategy 'silent' '# no output'
    Set-Option 'silent'
    Check 'empty stdout preserves the command' ((Resolve-Command) -ceq 'pwsh')
    Write-Strategy 'whitespace' "Write-Output '   '"
    Set-Option 'whitespace'
    Check 'whitespace stdout preserves the command' ((Resolve-Command) -ceq 'pwsh')
    Write-Strategy 'exit' 'Write-Output WRONG_COMMAND; exit 7'
    Set-Option 'exit'
    Check 'nonzero exit rejects stdout and preserves the command' ((Resolve-Command) -ceq 'pwsh')
    Write-Strategy 'throws' "Write-Output WRONG_COMMAND; throw 'strategy failed'"
    Set-Option 'throws'
    Check 'terminating error rejects stdout and preserves the command' ((Resolve-Command) -ceq 'pwsh')
    Write-Strategy 'syntax' 'param('
    Set-Option 'syntax'
    Check 'syntax error preserves the command' ((Resolve-Command) -ceq 'pwsh')

    foreach ($codePoint in 0x2018, 0x2019, 0x201A, 0x201B) {
        $quote = [char]$codePoint
        Set-Option 'arguments'
        $directory = "C:\work\O${quote}Brien"
        $actual = Resolve-Command "tool${quote}name" '1234' $directory
        $expected = "tool${quote}name|1234|$directory"
        Check "preserves Unicode quote U+$('{0:X4}' -f $codePoint) in arguments" `
            ([string]::Equals($actual, $expected, [StringComparison]::Ordinal)) $actual
        $smartDir = Join-Path $sandbox "O${quote}Brien"
        New-Item -ItemType Directory $smartDir -Force | Out-Null
        Copy-Item (Join-Path $userDir 'arguments.ps1') $smartDir
        $actual = Get-SaveCommand -PaneCommand 'pwsh' -PanePid '1234' -Directory $directory `
            -PsmuxBin $fake -PluginDir $plugin -UserStrategiesDir $smartDir
        Check "preserves Unicode quote U+$('{0:X4}' -f $codePoint) in script path" `
            ([string]::Equals($actual, "pwsh|1234|$directory", [StringComparison]::Ordinal)) $actual
        Set-Option 'silent'
        $directory = "C:\work\${quote}; Write-Output INJECTED; #${quote}"
        Check "Unicode quote U+$('{0:X4}' -f $codePoint) cannot execute argument text" `
            ((Resolve-Command 'pwsh' '1234' $directory) -ceq 'pwsh')
    }

    Set-Option 'default'
    $actual = Get-SaveCommand -PaneCommand 'nvim' -PanePid '99' -Directory $sandbox `
        -PsmuxBin $fake -PluginDir $plugin -UserStrategiesDir (Join-Path $sandbox 'absent')
    Check 'bundled default strategy echoes the original command' ($actual -ceq 'nvim') $actual
}
finally {
    Remove-Item $sandbox -Recurse -Force
}
Write-Host "Results: $pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
