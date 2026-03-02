#!/usr/bin/env pwsh
# Reads stdin and copies to Windows clipboard
param(
    [Parameter(ValueFromPipeline)]
    [string]$InputText
)
begin { $allText = @() }
process { $allText += $InputText }
end {
    $text = $allText -join "`n"
    if ($text) {
        Set-Clipboard -Value $text
    }
}