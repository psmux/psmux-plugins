# Psmux Plugin Developer Guide

## Porting tmux Plugins to Psmux

This guide helps **existing tmux plugin authors** port their plugins to psmux, and helps **new plugin developers** create plugins from scratch for the psmux ecosystem.

---

## Table of Contents

1. [How psmux Plugins Work](#how-psmux-plugins-work)
2. [Plugin File Structure](#plugin-file-structure)
3. [tmux vs psmux Command Mapping](#tmux-vs-psmux-command-mapping)
4. [Step-by-Step Porting Guide](#step-by-step-porting-guide)
5. [Key Differences from tmux](#key-differences-from-tmux)
6. [Plugin API Reference](#plugin-api-reference)
7. [Best Practices](#best-practices)
8. [Testing Your Plugin](#testing-your-plugin)
9. [Publishing Your Plugin](#publishing-your-plugin)
10. [Examples](#examples)

---

## How psmux Plugins Work

Psmux plugins use the same core mechanism as tmux plugins but with PowerShell instead of bash:

1. **User declares plugins** in `~/.psmux.conf` using `set -g @plugin 'owner/repo'`
2. **PPM (Psmux Plugin Manager)** clones plugins from GitHub to `~/.psmux/plugins/`
3. **On startup**, PPM sources each plugin's entry point script
4. **Plugins configure psmux** by calling `psmux` CLI commands (`set-option`, `bind-key`, `set-hook`, etc.)

### The Key Insight

Psmux is **fully tmux-command-compatible** (83 commands). Your plugin works by executing psmux commands from PowerShell scripts, just as tmux plugins execute tmux commands from bash scripts.

```
tmux plugin (bash):     tmux set-option -g mouse on
psmux plugin (PowerShell): psmux set-option -g mouse on   # IDENTICAL COMMAND
```

---

## Plugin File Structure

### Minimal Plugin

```
my-plugin/
  my-plugin.ps1      # Main entry point (PowerShell script)
  README.md          # Documentation
```

### Full Plugin

```
my-plugin/
  my-plugin.ps1      # Main entry point
  scripts/
    helper1.ps1      # Helper scripts (bound to keys, run by hooks)
    helper2.ps1
  README.md
  LICENSE
```

### Entry Point Resolution

PPM looks for the plugin entry point in this order:

1. `<plugin-name>/<plugin-name>.ps1`
2. `<plugin-name>/<name-without-psmux-prefix>.ps1`
3. `<plugin-name>/plugin.ps1`
4. `<plugin-name>/init.ps1`
5. `<plugin-name>/*.conf` (sourced via `psmux source-file`)

---

## tmux vs psmux Command Mapping

### Commands (Identical)

| tmux Command | psmux Command | Notes |
|-------------|---------------|-------|
| `tmux set-option -g key val` | `psmux set-option -g key val` | Identical syntax |
| `tmux bind-key ...` | `psmux bind-key ...` | Identical syntax |
| `tmux unbind-key ...` | `psmux unbind-key ...` | Identical syntax |
| `tmux set-hook -g ...` | `psmux set-hook -g ...` | Identical syntax |
| `tmux run-shell 'cmd'` | `psmux run-shell 'cmd'` | Identical syntax |
| `tmux display-message ...` | `psmux display-message ...` | Identical syntax |
| `tmux capture-pane ...` | `psmux capture-pane ...` | Identical syntax |
| `tmux pipe-pane ...` | `psmux pipe-pane ...` | Identical syntax |
| `tmux send-keys ...` | `psmux send-keys ...` | Identical syntax |
| `tmux if-shell ...` | `psmux if-shell ...` | Identical syntax |
| `tmux source-file ...` | `psmux source-file ...` | Identical syntax |
| `tmux list-panes` | `psmux list-panes` | Identical syntax |
| `tmux list-windows` | `psmux list-windows` | Identical syntax |
| `tmux show-options` | `psmux show-options` | Identical syntax |

All 76 psmux commands use tmux-identical syntax. **The binary is literally aliased as `tmux`**, so `tmux` commands work as-is.

### Shell Language Translation

This is the main difference. tmux plugins use bash; psmux plugins use PowerShell.

| Bash (tmux plugin) | PowerShell (psmux plugin) |
|--------------------|-----------------------------|
| `tmux show-option -gqv "@my_opt"` | `(psmux show-options -g -v '@my_opt' 2>&1 \| Out-String).Trim()` |
| `tmux set-option -g @my_opt "value"` | `psmux set -g @my_opt 'value'` |
| `local val=$(tmux ...)` | `$val = (psmux ... 2>&1 \| Out-String).Trim()` |
| `if [ "$val" = "on" ]; then` | `if ($val -eq 'on') {` |
| `echo "hello"` | `Write-Host "hello"` |
| `cat file.txt` | `Get-Content file.txt` |
| `grep pattern file` | `Select-String -Pattern 'pattern' file` |
| `sed 's/a/b/g'` | `-replace 'a','b'` |
| `basename "$path"` | `Split-Path -Leaf $path` |
| `dirname "$path"` | `Split-Path -Parent $path` |
| `[ -f "$file" ]` | `Test-Path $file` |
| `mkdir -p "$dir"` | `New-Item -ItemType Directory -Path $dir -Force` |
| `xclip -selection clipboard` | `Set-Clipboard -Value $text` |
| `xdg-open "$url"` | `Start-Process $url` |
| `uname -s` | `$env:OS` (always "Windows_NT") |
| `$HOME` | `$env:USERPROFILE` |
| `~/.tmux/...` | `$env:USERPROFILE\.psmux\...` |

### Clipboard Translation

| Platform | tmux (bash) | psmux (PowerShell) |
|----------|-------------|---------------------|
| Copy | `xclip -selection clipboard` / `pbcopy` | `Set-Clipboard` |
| Paste | `xclip -o` / `pbpaste` | `Get-Clipboard` |

### Process Management Translation

| Bash | PowerShell |
|------|------------|
| `pgrep -f "pattern"` | `Get-Process \| Where-Object { $_.CommandLine -match 'pattern' }` |
| `kill $pid` | `Stop-Process -Id $pid` |
| `nohup cmd &` | `Start-Job { cmd }` or `Start-Process -WindowStyle Hidden` |
| `command -v tool` | `Get-Command tool -ErrorAction SilentlyContinue` |

### System Info Translation

| Bash | PowerShell |
|------|------------|
| `cat /proc/stat` | `Get-CimInstance Win32_Processor` |
| `free -m` | `Get-CimInstance Win32_OperatingSystem` |
| `acpi -b` / `pmset -g batt` | `Get-CimInstance Win32_Battery` |
| `df -h` | `Get-PSDrive -PSProvider FileSystem` |
| `uptime` | `(Get-CimInstance Win32_OperatingSystem).LastBootUpTime` |

---

## Step-by-Step Porting Guide

### Step 1: Analyze Your tmux Plugin

Identify what your plugin does:
- What **tmux commands** does it call?
- What **shell commands** does it use (bash, grep, sed, awk)?
- What **external tools** does it depend on (xclip, fzf, tree)?
- What **hooks** does it register?
- What **key bindings** does it create?
- What **status bar format strings** does it inject?

### Step 2: Create the PowerShell Entry Point

Convert your main bash script to PowerShell:

**tmux plugin (bash):**
```bash
#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS_DIR="$CURRENT_DIR/scripts"

# Get option
get_tmux_option() {
    local option=$1
    local default_value=$2
    local value=$(tmux show-option -gqv "$option")
    if [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Set key bindings
tmux bind-key y run-shell "$SCRIPTS_DIR/copy.sh"
tmux bind-key p run-shell "$SCRIPTS_DIR/paste.sh"

# Set hooks
tmux set-hook -g client-attached "run-shell '$SCRIPTS_DIR/on_attach.sh'"
```

**psmux plugin (PowerShell):**
```powershell
#!/usr/bin/env pwsh

$SCRIPTS_DIR = Join-Path $PSScriptRoot 'scripts'

# Detect psmux binary
function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}
$PSMUX = Get-PsmuxBin

# Get option (equivalent of get_tmux_option)
function Get-PsmuxOption {
    param([string]$Name, [string]$Default)
    $val = (& $PSMUX show-options -g -v $Name 2>&1 | Out-String).Trim()
    if ($val -and $val -notmatch 'unknown|error|invalid') { return $val }
    return $Default
}

# Set key bindings
& $PSMUX bind-key y "run-shell 'pwsh -NoProfile -File \"$SCRIPTS_DIR/copy.ps1\"'" 2>&1 | Out-Null
& $PSMUX bind-key p "run-shell 'pwsh -NoProfile -File \"$SCRIPTS_DIR/paste.ps1\"'" 2>&1 | Out-Null

# Set hooks
$attachScript = (Join-Path $SCRIPTS_DIR 'on_attach.ps1') -replace '\\','/'
& $PSMUX set-hook -g client-attached "run-shell 'pwsh -NoProfile -File \"$attachScript\"'" 2>&1 | Out-Null

Write-Host "my-plugin: loaded" -ForegroundColor DarkGray
```

### Step 3: Convert Helper Scripts

For each bash helper script, create a PowerShell equivalent.

**Bash (`scripts/copy.sh`):**
```bash
#!/usr/bin/env bash
tmux capture-pane -J
content=$(tmux show-buffer)
echo "$content" | xclip -selection clipboard
tmux display-message "Copied to clipboard!"
```

**PowerShell (`scripts/copy.ps1`):**
```powershell
#!/usr/bin/env pwsh
$PSMUX = (Get-Command psmux,pmux,tmux -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $PSMUX) { $PSMUX = 'psmux' }

& $PSMUX capture-pane -J 2>&1 | Out-Null
$content = & $PSMUX show-buffer 2>&1 | Out-String
Set-Clipboard -Value $content
& $PSMUX display-message "Copied to clipboard!" 2>&1 | Out-Null
```

### Step 4: Replace External Tool Dependencies

| Unix Tool | Windows / PowerShell Equivalent |
|-----------|-------------------------------|
| `xclip` / `pbcopy` | `Set-Clipboard` / `Get-Clipboard` |
| `xdg-open` / `open` | `Start-Process` |
| `tree` | `tree /F /A` (Windows tree) or `Get-ChildItem -Recurse` |
| `fzf` | `fzf` (install via scoop/choco/winget) |
| `grep` | `Select-String` |
| `sed` | `-replace` operator |
| `awk` | `ForEach-Object` with regex |
| `curl` / `wget` | `Invoke-WebRequest` or `Invoke-RestMethod` |
| `date` | `Get-Date -Format 'yyyyMMdd'` |
| `sleep` | `Start-Sleep -Seconds N` |
| `mktemp` | `[System.IO.Path]::GetTempFileName()` |

### Step 5: Handle Platform-Specific Code

Many tmux plugins have platform detection. In psmux, it's always Windows:

**tmux plugin (bash):**
```bash
if [[ "$(uname)" == "Darwin" ]]; then
    copy_cmd="pbcopy"
elif command -v xclip &>/dev/null; then
    copy_cmd="xclip -selection clipboard"
fi
```

**psmux plugin (PowerShell):**
```powershell
# On psmux, it's always Windows - use native clipboard
$copyCmd = { param($text) Set-Clipboard -Value $text }
```

### Step 6: Handle `run-shell` Script Invocations

tmux `run-shell` runs bash by default. In psmux on Windows, you need to specify PowerShell:

```
# tmux (bash is the default shell for run-shell)
tmux run-shell "~/.tmux/plugins/myplugin/scripts/do_thing.sh"

# psmux (must specify pwsh for PowerShell scripts)
psmux run-shell "pwsh -NoProfile -File '~/.psmux/plugins/myplugin/scripts/do_thing.ps1'"

# OR if the script is a simple one-liner:
psmux run-shell "pwsh -NoProfile -Command 'Get-Date | Set-Clipboard'"
```

### Step 7: Update File Paths

| tmux (Unix) | psmux (Windows) |
|-------------|-----------------|
| `~/.tmux/` | `~/.psmux/` or `$env:USERPROFILE\.psmux\` |
| `~/.tmux/plugins/` | `~/.psmux/plugins/` |
| `~/.tmux.conf` | `~/.psmux.conf` |
| `/tmp/` | `$env:TEMP\` or `[System.IO.Path]::GetTempPath()` |
| `/dev/null` | `$null` |
| Path separator: `/` | Path separator: `\` (but `/` works in most cases) |

---

## Key Differences from tmux

### 1. Shell for `run-shell`

tmux defaults to `$SHELL` (usually bash). psmux on Windows defaults to the system shell. Always be explicit:

```powershell
# Explicit PowerShell invocation
& $PSMUX run-shell "pwsh -NoProfile -File 'script.ps1'" 2>&1 | Out-Null
```

### 2. User Options (@ variables)

Both tmux and psmux support user-defined `@` variables:

```powershell
# Set a user option
& $PSMUX set -g '@my-plugin-option' 'value' 2>&1 | Out-Null

# Read a user option
$val = (& $PSMUX show-options -g -v '@my-plugin-option' 2>&1 | Out-String).Trim()
```

### 3. Format Variables

psmux supports 140+ format variables identical to tmux:

```powershell
# These all work the same as tmux
$sessionName = (& $PSMUX display-message -p '#{session_name}' 2>&1 | Out-String).Trim()
$paneId = (& $PSMUX display-message -p '#{pane_id}' 2>&1 | Out-String).Trim()
$windowIndex = (& $PSMUX display-message -p '#{window_index}' 2>&1 | Out-String).Trim()
```

### 4. Hooks

psmux supports 15+ hooks identical to tmux:

```powershell
# Available hooks (same as tmux):
# after-new-session, after-new-window, after-split-window,
# client-attached, client-detached, after-select-pane,
# after-select-window, after-resize-pane, pane-exited, etc.

& $PSMUX set-hook -g after-new-window "run-shell 'pwsh -NoProfile -Command { ... }'" 2>&1 | Out-Null
```

### 5. Config Files

psmux reads these config files (first found wins):

1. `~/.psmux.conf` (preferred for psmux-specific config)
2. `~/.psmuxrc`
3. `~/.tmux.conf` (backward compatibility with tmux)
4. `~/.config/psmux/psmux.conf`

### 6. Binary Names

psmux ships as three identical binaries: `psmux`, `pmux`, and `tmux`. Your plugin should detect whichever is available:

```powershell
function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}
```

### 7. CRITICAL: Case-Insensitive Key Bindings

**psmux normalizes key bindings case-insensitively.** `H` and `h` are treated as the SAME key. The uppercase binding overwrites the lowercase one.

```powershell
# WRONG — H will overwrite h!
& $PSMUX bind-key h select-pane -L
& $PSMUX bind-key H resize-pane -L 5   # This REPLACES h!

# CORRECT — use Alt modifier for the second set
& $PSMUX bind-key h select-pane -L     # Navigation
& $PSMUX bind-key M-h resize-pane -L 5 # Resize (different binding)
```

This affects all letter keys (`Y`/`y`, `D`/`d`, `P`/`p`, etc.). When porting tmux plugins that use both cases of the same letter, use `M-` (Alt) or `C-` (Ctrl) modifiers instead of Shift.

### 8. CRITICAL: Backslashes Stripped in Bind-Key

**psmux strips backslashes from command strings in `bind-key`.** Windows paths like `C:\Users\...` will become `C:Users...`.

```powershell
# WRONG — backslashes are eaten
$path = 'C:\Users\name\script.ps1'
& $PSMUX bind-key x "run-shell 'pwsh -File \"$path\"'"
# Result: C:Usersnamescript.ps1  (BROKEN!)

# CORRECT — convert to forward slashes first
$path = ($scriptPath -replace '\\', '/')
& $PSMUX bind-key x "run-shell 'pwsh -File \"$path\"'"
# Result: C:/Users/name/script.ps1  (WORKS!)
```

**Always convert paths to forward slashes** before passing them to `bind-key`, `set-hook`, or any psmux command that stores commands for later execution.

### 9. CRITICAL: Avoid Inline PowerShell in Bind-Key

Complex PowerShell commands embedded directly in `bind-key` strings break due to nested escaping issues. **Always use external script files**.

```powershell
# WRONG — escaping nightmare, variables expand at wrong time
& $PSMUX bind-key b "run-shell 'pwsh -Command { `$x = Get-Something; psmux display-message \"`$x\" }'"

# CORRECT — create an external script, bind to that
$script = @'
$x = Get-Something
psmux display-message "$x"
'@
Set-Content -Path "$SCRIPTS_DIR/info.ps1" -Value $script
$fwdPath = "$SCRIPTS_DIR/info.ps1" -replace '\\', '/'
& $PSMUX bind-key b "run-shell 'pwsh -NoProfile -File \"$fwdPath\"'"
```

---

## Plugin API Reference

### Standard Boilerplate

Every psmux plugin should start with:

```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Continue'

function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}

$PSMUX = Get-PsmuxBin

function Get-PsmuxOption {
    param([string]$Name, [string]$Default)
    $val = (& $PSMUX show-options -g -v $Name 2>&1 | Out-String).Trim()
    if ($val -and $val -notmatch 'unknown|error|invalid') { return $val }
    return $Default
}
```

### Setting Options

```powershell
& $PSMUX set -g option-name 'value' 2>&1 | Out-Null
& $PSMUX set -g @custom-option 'value' 2>&1 | Out-Null   # @ prefix for plugin options
```

### Reading Options

```powershell
$val = Get-PsmuxOption 'option-name' 'default-value'
$custom = Get-PsmuxOption '@my-plugin-opt' 'default'
```

### Binding Keys

```powershell
# Simple binding
& $PSMUX bind-key X kill-pane 2>&1 | Out-Null

# Binding with script execution
& $PSMUX bind-key X "run-shell 'pwsh -NoProfile -File \"$scriptPath\"'" 2>&1 | Out-Null

# Repeatable binding
& $PSMUX bind-key -r H resize-pane -L 5 2>&1 | Out-Null

# No-prefix binding
& $PSMUX bind-key -n C-h select-pane -L 2>&1 | Out-Null

# Copy-mode binding
& $PSMUX bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'clip-cmd' 2>&1 | Out-Null
```

### Setting Hooks

```powershell
& $PSMUX set-hook -g after-new-window "run-shell 'pwsh -NoProfile -File \"$hookScript\"'" 2>&1 | Out-Null
```

### Modifying Status Bar

```powershell
# Read current status-right
$current = Get-PsmuxOption 'status-right' '%H:%M'

# Prepend your content
& $PSMUX set -g status-right "#{?client_prefix,WAIT,} $current" 2>&1 | Out-Null
```

### Getting Session/Pane Info

```powershell
$sessionName = (& $PSMUX display-message -p '#{session_name}' 2>&1 | Out-String).Trim()
$paneDir = (& $PSMUX display-message -p '#{pane_current_path}' 2>&1 | Out-String).Trim()
$paneId = (& $PSMUX display-message -p '#{pane_id}' 2>&1 | Out-String).Trim()
$windowCount = (& $PSMUX display-message -p '#{session_windows}' 2>&1 | Out-String).Trim()
```

### Capturing Pane Content

```powershell
& $PSMUX capture-pane -J 2>&1 | Out-Null
$content = & $PSMUX show-buffer 2>&1 | Out-String

# Capture full history
& $PSMUX capture-pane -S - -E - -J 2>&1 | Out-Null
$fullHistory = & $PSMUX show-buffer 2>&1 | Out-String
```

### Running Shell Commands

```powershell
# Fire-and-forget
& $PSMUX run-shell "pwsh -NoProfile -Command 'do-something'" 2>&1 | Out-Null

# From config file context
& $PSMUX run-shell "pwsh -NoProfile -File '$scriptPath'" 2>&1 | Out-Null
```

---

## Best Practices

### 1. Always Use `2>&1 | Out-Null` for Side-Effect Commands

```powershell
# Good: suppress output for commands that configure psmux
& $PSMUX set -g mouse on 2>&1 | Out-Null

# Bad: output noise during plugin loading
& $PSMUX set -g mouse on
```

### 2. Use `@` Prefix for Plugin-Specific Options

```powershell
# Good: namespaced with @
& $PSMUX set -g '@my-plugin-interval' '15' 2>&1 | Out-Null

# Bad: could conflict with built-in options
& $PSMUX set -g 'my-plugin-interval' '15' 2>&1 | Out-Null
```

### 3. Provide Sensible Defaults

```powershell
$interval = Get-PsmuxOption '@my-plugin-interval' '15'  # Default 15 if not set
```

### 4. Log Minimally

```powershell
# Good: single quiet line
Write-Host "my-plugin: loaded" -ForegroundColor DarkGray

# Bad: verbose output during loading
Write-Host "Loading my-plugin..."
Write-Host "Setting keybindings..."
Write-Host "Registering hooks..."
Write-Host "Done!"
```

### 5. Handle Missing Dependencies Gracefully

```powershell
$hasFzf = Get-Command fzf -ErrorAction SilentlyContinue
if (-not $hasFzf) {
    Write-Host "my-plugin: fzf not found, some features disabled" -ForegroundColor Yellow
    return
}
```

### 6. Use Full Paths in Scripts Called by Hooks/Bindings

```powershell
# Good: absolute path
$scriptPath = (Join-Path $SCRIPTS_DIR 'my_script.ps1') -replace '\\', '/'
& $PSMUX bind-key X "run-shell 'pwsh -NoProfile -File \"$scriptPath\"'" 2>&1 | Out-Null

# Bad: relative path (may fail depending on CWD)
& $PSMUX bind-key X "run-shell 'pwsh my_script.ps1'" 2>&1 | Out-Null
```

### 7. Test Binary Detection

Support all three psmux binary names:

```powershell
function Get-PsmuxBin {
    foreach ($n in @('psmux','pmux','tmux')) {
        $b = Get-Command $n -ErrorAction SilentlyContinue
        if ($b) { return $b.Source }
    }
    return 'psmux'
}
```

---

## Testing Your Plugin

### Manual Testing

```powershell
# 1. Start a psmux session
psmux new-session -d -s test

# 2. Source your plugin
pwsh -NoProfile -File path/to/your-plugin.ps1

# 3. Verify keybindings
psmux list-keys -t test

# 4. Verify options
psmux show-options -t test

# 5. Verify hooks
psmux show-hooks -t test
```

### Automated Test Script

Create `tests/test.ps1`:

```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0

function Check($name, $cond) {
    if ($cond) { Write-Host "  PASS: $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL: $name" -ForegroundColor Red; $script:fail++ }
}

$PSMUX = (Get-Command psmux,pmux,tmux -EA SilentlyContinue | Select-Object -First 1).Source
$SESSION = "plugin_test_$(Get-Random)"

# Setup
Start-Process -FilePath $PSMUX -ArgumentList "new-session", "-d", "-s", $SESSION -WindowStyle Hidden
Start-Sleep -Seconds 3

# Load plugin
& "$PSScriptRoot\..\my-plugin.ps1"
Start-Sleep -Seconds 1

# Test: keybinding registered
$keys = & $PSMUX list-keys -t $SESSION 2>&1 | Out-String
Check "keybinding registered" ($keys -match 'my-expected-binding')

# Test: option set
$opts = & $PSMUX show-options -t $SESSION -g 2>&1 | Out-String
Check "option set" ($opts -match '@my-option')

# Cleanup
& $PSMUX kill-session -t $SESSION 2>&1 | Out-Null

Write-Host "`nResults: $pass passed, $fail failed"
exit $fail
```

---

## Publishing Your Plugin

### 1. Repository Structure

```
your-psmux-plugin/
  your-psmux-plugin.ps1    # Required: main entry point
  scripts/                 # Optional: helper scripts
  tests/                   # Recommended: test scripts
  README.md                # Required: documentation
  LICENSE                  # Recommended: MIT
```

### 2. Naming Convention

- Use the prefix `psmux-` for psmux-native plugins: `psmux-my-feature`
- If porting from tmux, use the same name with `psmux-` prefix: `tmux-yank` -> `psmux-yank`

### 3. README Template

```markdown
# psmux-my-feature

Brief description. Port of [tmux-feature](link) (if applicable).

## Installation (via PPM)

\```tmux
set -g @plugin 'your-org/psmux-my-feature'
\```

## Key Bindings

| Key | Action |
|-----|--------|
| ... | ... |

## Options

\```tmux
set -g @my-feature-option 'value'
\```

## License

MIT
```

### 4. Publish to GitHub

```powershell
git init
git add .
git commit -m "Initial release"
gh repo create your-org/psmux-my-feature --public --source .
git push -u origin main
```

Users install with:
```tmux
set -g @plugin 'your-org/psmux-my-feature'
```

---

## Examples

### Example 1: Simple Status Bar Plugin

```powershell
#!/usr/bin/env pwsh
# psmux-clock - Show a fancy clock in status bar

$PSMUX = (Get-Command psmux,pmux,tmux -EA SilentlyContinue | Select-Object -First 1).Source
if (-not $PSMUX) { $PSMUX = 'psmux' }

$clockFormat = '%H:%M:%S %d-%b-%Y'
& $PSMUX set -g status-right " $clockFormat " 2>&1 | Out-Null
& $PSMUX set -g status-interval 1 2>&1 | Out-Null  # Update every second

Write-Host "psmux-clock: loaded" -ForegroundColor DarkGray
```

### Example 2: Keybinding Plugin

```powershell
#!/usr/bin/env pwsh
# psmux-quick-split - Quick split presets

$PSMUX = (Get-Command psmux,pmux,tmux -EA SilentlyContinue | Select-Object -First 1).Source
if (-not $PSMUX) { $PSMUX = 'psmux' }

# Prefix+Ctrl+h: 3-pane horizontal layout
& $PSMUX bind-key C-h "split-window -h; split-window -h; select-layout even-horizontal" 2>&1 | Out-Null

# Prefix+Ctrl+v: 3-pane vertical layout
& $PSMUX bind-key C-v "split-window -v; split-window -v; select-layout even-vertical" 2>&1 | Out-Null

# Prefix+Ctrl+t: 4-pane tiled layout
& $PSMUX bind-key C-t "split-window -h; split-window -v; select-pane -t 0; split-window -v; select-layout tiled" 2>&1 | Out-Null

Write-Host "psmux-quick-split: loaded" -ForegroundColor DarkGray
```

### Example 3: Hook-Based Plugin

```powershell
#!/usr/bin/env pwsh
# psmux-notify - Desktop notifications for pane activity

$PSMUX = (Get-Command psmux,pmux,tmux -EA SilentlyContinue | Select-Object -First 1).Source
if (-not $PSMUX) { $PSMUX = 'psmux' }

$SCRIPTS_DIR = Join-Path $PSScriptRoot 'scripts'
New-Item -ItemType Directory -Path $SCRIPTS_DIR -Force | Out-Null

# Create notification script
$notifyScript = @'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText01)
$textNodes = $template.GetElementsByTagName("text")
$textNodes.Item(0).AppendChild($template.CreateTextNode("psmux: Activity detected!")) | Out-Null
$toast = [Windows.UI.Notifications.ToastNotification]::new($template)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("psmux").Show($toast)
'@

Set-Content -Path (Join-Path $SCRIPTS_DIR 'notify.ps1') -Value $notifyScript -Force

# Enable monitor-activity and set hook
& $PSMUX set -g monitor-activity on 2>&1 | Out-Null
$notifyPath = (Join-Path $SCRIPTS_DIR 'notify.ps1') -replace '\\','/'
& $PSMUX set-hook -g alert-activity "run-shell 'pwsh -NoProfile -File \"$notifyPath\"'" 2>&1 | Out-Null

Write-Host "psmux-notify: loaded" -ForegroundColor DarkGray
```

---

## Quick Reference: Porting Checklist

- [ ] Create `<plugin-name>/<plugin-name>.ps1` entry point
- [ ] Replace `#!/usr/bin/env bash` with `#!/usr/bin/env pwsh`
- [ ] Replace `tmux` with `$PSMUX` variable (detected dynamically)
- [ ] Replace `$()` subshells with `(... | Out-String).Trim()`
- [ ] Replace `[ -z "$var" ]` with `if (-not $var)`
- [ ] Replace `echo` with `Write-Host` or `Write-Output`
- [ ] Replace `cat/grep/sed/awk` with PowerShell equivalents
- [ ] Replace `xclip`/`pbcopy` with `Set-Clipboard`/`Get-Clipboard`
- [ ] Replace Unix paths (`~/`) with `$env:USERPROFILE\`
- [ ] Replace `.tmux` directories with `.psmux`
- [ ] Replace bash scripts in `run-shell` with `pwsh -NoProfile -File`
- [ ] Wrap psmux commands with `2>&1 | Out-Null` for config commands
- [ ] Add `$ErrorActionPreference = 'Continue'` at top
- [ ] Add binary detection boilerplate (`Get-PsmuxBin`)
- [ ] Test with `psmux list-keys` and `psmux show-options`
- [ ] Write README with PPM install instructions
