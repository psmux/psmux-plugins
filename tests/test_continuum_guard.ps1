#!/usr/bin/env pwsh
# =============================================================================
# psmux-continuum: auto-save break-on-empty + here-string drift guard (PR2)
# =============================================================================
# Static, hermetic asserts (no server, no binary): the auto-save loop must treat
# empty `psmux ls` output as "no server", and the committed scripts/auto_save.ps1
# must stay byte-identical to the here-string in psmux-continuum.ps1 that
# regenerates it on every plugin load (Set-Content -Force) -- otherwise a reload
# silently reverts the single-instance mutex from #24 (and this break-on-empty).
# Run:  pwsh -File tests/test_continuum_guard.ps1
# =============================================================================
$ErrorActionPreference = 'Continue'

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else       { Write-Host "  FAIL: $name$(if($detail){' >> ' + $detail})" -ForegroundColor Red; $script:fail++ }
}

$PLUGIN_ROOT = Split-Path $PSScriptRoot -Parent
$AUTO_SAVE   = Join-Path $PLUGIN_ROOT 'psmux-continuum\scripts\auto_save.ps1'
$CONTINUUM   = Join-Path $PLUGIN_ROOT 'psmux-continuum\psmux-continuum.ps1'

Write-Host "`n=== psmux-continuum break-on-empty / drift guard ===" -ForegroundColor Magenta

$autoRaw = Get-Content $AUTO_SAVE -Raw
$contRaw = Get-Content $CONTINUUM -Raw

# break-on-empty present in BOTH copies (committed file AND the here-string generator)
Check "committed auto_save.ps1 breaks on empty output"        ($autoRaw.Contains('-not $sessions.Trim()'))
Check "psmux-continuum.ps1 here-string breaks on empty output" ($contRaw.Contains('-not $sessions.Trim()'))

# both retain the #24 single-instance mutex (so neither path drops it)
Check "both copies retain the #24 single-instance mutex" `
    ($autoRaw.Contains('psmux-continuum-autosave') -and $contRaw.Contains('psmux-continuum-autosave'))

# the here-string regenerates byte-identical to the committed file (drift guard).
# NB: compares the embedded literal rather than executing psmux-continuum.ps1 (which
# has side effects: Start-Job, psmux calls). A future rename of $autoSaveScript would
# make the regex miss -> empty $heredoc -> this fails LOUDLY, which is the safe outcome.
$m = [regex]::Match($contRaw, "(?s)\`$autoSaveScript = @'\r?\n(.*?)\r?\n'@")
$heredoc   = ($m.Groups[1].Value      -replace "`r`n","`n").TrimEnd("`n")
$committed = ((Get-Content $AUTO_SAVE -Raw) -replace "`r`n","`n").TrimEnd("`n")
Check "here-string was found in psmux-continuum.ps1" ($m.Success)
Check "here-string regenerates byte-identical to committed auto_save.ps1" ($heredoc -ceq $committed)

# --- Behavioral proof of the break DECISION ---------------------------------
# The full loop can't be run in a unit test (it sleeps IntervalMinutes*60 then holds a
# process-wide named mutex), so prove the decision the fix encodes directly. This mirrors
# the exact condition in auto_save.ps1; the static asserts above prove that condition is
# the one actually shipped in both copies.
$break = { param([int]$code, [string]$out) ($code -ne 0) -or (-not $out.Trim()) }
Check "decision: server DOWN (exit 0, empty) -> break  [the bug the fix closes]" (& $break 0 '')
Check "decision: server DOWN (exit 0, whitespace) -> break"                       (& $break 0 "  `n ")
Check "decision: server UP (exit 0, real sessions) -> keep looping"        (-not (& $break 0 "agents: 1 windows (created ...)"))
Check "decision: hard error (exit 1) -> break"                                    (& $break 1 'error: connect failed')

# --- Premise proof (the reason the OLD exit-code-only check failed) ----------
# The whole bug rests on: psmux returns EXIT 0 with EMPTY output when no server exists.
# Prove it with the REAL binary against a THROWAWAY socket -- this does NOT touch the
# user's default server. Skips cleanly if no psmux is installed (keeps the suite runnable
# on a binary-less/CI box).
$psmuxBin = $null
foreach ($n in 'psmux','pmux','tmux') { $c = Get-Command $n -ErrorAction SilentlyContinue; if ($c) { $psmuxBin = $c.Source; break } }
if ($psmuxBin) {
    $sock = 'psmux-guardtest-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
    $premiseOut = & $psmuxBin -L $sock ls 2>&1 | Out-String
    $premiseCode = $LASTEXITCODE
    Check "PREMISE: real psmux '-L <no server> ls' exits 0 (not non-zero)" ($premiseCode -eq 0) "exit=$premiseCode"
    Check "PREMISE: real psmux '-L <no server> ls' emits empty output"     (-not $premiseOut.Trim()) "out=[$($premiseOut.Trim())]"
} else {
    Write-Host "  SKIP: no psmux binary on PATH -> premise check skipped" -ForegroundColor DarkGray
}

Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
