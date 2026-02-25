#!/usr/bin/env pwsh
# =============================================================================
# psmux-yank - Windows clipboard integration for psmux
# Port of tmux-plugins/tmux-yank for psmux
# =============================================================================
#
# Copies psmux selections and pane content to the Windows clipboard.
# Uses native Windows clipboard APIs (no external tools needed).
#
# Options (set in ~/.psmux.conf):
#   set -g @yank_selection 'clipboard'    # 'clipboard' (default) or 'primary'
#   set -g @yank_action 'copy-pipe'       # 'copy-pipe' (stay in copy mode) or
#                                         # 'copy-pipe-and-cancel' (exit copy mode)
#   set -g @yank_with_mouse 'on'          # Copy mouse selections to clipboard
# =============================================================================

$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin
$SCRIPTS_DIR = Join-Path $PSScriptRoot 'scripts'

# Ensure scripts directory exists
if (-not (Test-Path $SCRIPTS_DIR)) {
    New-Item -ItemType Directory -Path $SCRIPTS_DIR -Force | Out-Null
}

# --- Create the clipboard helper script ---
$clipScript = @'
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
'@

$clipScriptPath = Join-Path $SCRIPTS_DIR 'copy_to_clipboard.ps1'
Set-Content -Path $clipScriptPath -Value $clipScript -NoNewline -Force

# --- Create paste helper ---
$pasteScript = @'
#!/usr/bin/env pwsh
# Reads clipboard and outputs to stdout
Get-Clipboard | Write-Output
'@

$pasteScriptPath = Join-Path $SCRIPTS_DIR 'paste_from_clipboard.ps1'
Set-Content -Path $pasteScriptPath -Value $pasteScript -NoNewline -Force

# --- Bind copy-mode keys ---
# In vi copy mode: 'y' copies selection to clipboard
# NOTE: Convert backslashes to forward slashes — psmux strips backslashes
#       in bind-key arguments, breaking Windows paths.
# NOTE: psmux treats key bindings case-insensitively (Y == y), so we use
#       Alt-y / Alt-d for the extended copy operations.
$copyCmd = ("pwsh -NoProfile -File `"$clipScriptPath`"") -replace '\\', '/'

# Bind 'y' in copy-mode-vi to copy to clipboard
& $PSMUX bind-key -T copy-mode-vi y "send-keys -X copy-pipe-and-cancel '$copyCmd'" 2>&1 | Out-Null

# Bind Enter in copy-mode-vi to copy to clipboard
& $PSMUX bind-key -T copy-mode-vi Enter "send-keys -X copy-pipe-and-cancel '$copyCmd'" 2>&1 | Out-Null

# Bind Alt-y to copy entire line to clipboard (avoids Y/y case conflict)
& $PSMUX bind-key -T copy-mode-vi M-y "send-keys -X select-line; send-keys -X copy-pipe-and-cancel '$copyCmd'" 2>&1 | Out-Null

# Bind Alt-d to copy from cursor to end of line (avoids D/d case conflict)
& $PSMUX bind-key -T copy-mode-vi M-d "send-keys -X copy-end-of-line '$copyCmd'" 2>&1 | Out-Null

# --- Normal mode bindings ---
# Prefix + y: Copy entire visible pane content to clipboard
& $PSMUX bind-key y "capture-pane -J; run-shell 'pwsh -NoProfile -Command { psmux show-buffer | Set-Clipboard }'" 2>&1 | Out-Null

# Prefix + Alt-y: Copy current pane's working directory to clipboard
# (avoids Y/y case conflict)
& $PSMUX bind-key M-y "run-shell 'pwsh -NoProfile -Command { (psmux display-message -p \"#{pane_current_path}\") | Set-Clipboard; psmux display-message \"Path copied to clipboard\" }'" 2>&1 | Out-Null

Write-Host "psmux-yank: loaded" -ForegroundColor DarkGray
