# Psmux Plugins

The official plugin ecosystem for [psmux](https://github.com/marlocarlo/psmux) — the native Windows tmux built in Rust.

Ports of the most popular tmux plugins, reimplemented in PowerShell for Windows.

---

## Quick Start

### 1. Install PPM (Psmux Plugin Manager)

```powershell
git clone https://github.com/marlocarlo/psmux-plugins.git "$env:TEMP\psmux-plugins" ; Copy-Item "$env:TEMP\psmux-plugins\ppm" "$env:USERPROFILE\.psmux\plugins\ppm" -Recurse ; Remove-Item "$env:TEMP\psmux-plugins" -Recurse -Force
```

### 2. Configure Plugins

Add to your `~/.psmux.conf`:

```tmux
# ===========================================
# Plugins
# ===========================================
set -g @plugin 'psmux-plugins/ppm'
set -g @plugin 'psmux-plugins/psmux-sensible'
set -g @plugin 'psmux-plugins/psmux-yank'
set -g @plugin 'psmux-plugins/psmux-resurrect'
set -g @plugin 'psmux-plugins/psmux-pain-control'

# Initialize PPM (keep at the very bottom)
run '~/.psmux/plugins/ppm/ppm.ps1'
```

### 3. Install Plugins

Start psmux and press `Prefix + I` (capital I) to install.

---

## Available Plugins

| Plugin | Description | Tmux Equivalent |
|--------|-------------|-----------------|
| [**ppm**](ppm/) | Plugin manager | [tpm](https://github.com/tmux-plugins/tpm) |
| [**psmux-sensible**](psmux-sensible/) | Sensible defaults | [tmux-sensible](https://github.com/tmux-plugins/tmux-sensible) |
| [**psmux-yank**](psmux-yank/) | Windows clipboard integration | [tmux-yank](https://github.com/tmux-plugins/tmux-yank) |
| [**psmux-resurrect**](psmux-resurrect/) | Save/restore sessions | [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) |
| [**psmux-continuum**](psmux-continuum/) | Auto-save/restore | [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) |
| [**psmux-pain-control**](psmux-pain-control/) | Better pane navigation | [tmux-pain-control](https://github.com/tmux-plugins/tmux-pain-control) |
| [**psmux-prefix-highlight**](psmux-prefix-highlight/) | Prefix key indicator | [tmux-prefix-highlight](https://github.com/tmux-plugins/tmux-prefix-highlight) |
| [**psmux-battery**](psmux-battery/) | Battery status bar | [tmux-battery](https://github.com/tmux-plugins/tmux-battery) |
| [**psmux-cpu**](psmux-cpu/) | CPU/memory status bar | [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu) |
| [**psmux-logging**](psmux-logging/) | Pane output logging | [tmux-logging](https://github.com/tmux-plugins/tmux-logging) |
| [**psmux-sidebar**](psmux-sidebar/) | Directory tree sidebar | [tmux-sidebar](https://github.com/tmux-plugins/tmux-sidebar) |

### Theme Plugins

| Theme | Description | Tmux Equivalent |
|-------|-------------|-----------------|
| [**psmux-theme-dracula**](psmux-theme-dracula/) | Dracula dark theme | [tmux-dracula](https://github.com/dracula/tmux) |
| [**psmux-theme-catppuccin**](psmux-theme-catppuccin/) | Catppuccin pastel theme (4 flavors) | [catppuccin/tmux](https://github.com/catppuccin/tmux) |
| [**psmux-theme-nord**](psmux-theme-nord/) | Nord arctic theme | [nord-tmux](https://github.com/arcticicestudio/nord-tmux) |
| [**psmux-theme-tokyonight**](psmux-theme-tokyonight/) | Tokyo Night theme (3 styles) | [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) |
| [**psmux-theme-gruvbox**](psmux-theme-gruvbox/) | Gruvbox retro theme (dark/light) | [tmux-gruvbox](https://github.com/egel/tmux-gruvbox) |

---

## Key Bindings Summary

### PPM (Plugin Manager)
| Key | Action |
|-----|--------|
| `Prefix + I` | Install plugins |
| `Prefix + U` | Update plugins |
| `Prefix + M` | Remove unused plugins |

### psmux-sensible
| Key | Action |
|-----|--------|
| `Prefix + R` | Reload config |
| `Prefix + \|` | Split horizontal |
| `Prefix + -` | Split vertical |
| `Shift + Left/Right` | Prev/next window (no prefix) |

### psmux-yank
| Key | Action |
|-----|--------|
| `y` (copy mode) | Copy to clipboard |
| `Prefix + y` | Copy pane content |
| `Prefix + Alt-y` | Copy working directory |

### psmux-resurrect
| Key | Action |
|-----|--------|
| `Prefix + Ctrl-s` | Save environment |
| `Prefix + Ctrl-r` | Restore environment |

### psmux-pain-control
| Key | Action |
|-----|--------|
| `Prefix + h/j/k/l` | Navigate panes (vim) |
| `Prefix + Alt-h/j/k/l` | Resize panes |
| `Prefix + \|` or `\` | Split horizontal |
| `Prefix + -` or `_` | Split vertical |

### psmux-logging
| Key | Action |
|-----|--------|
| `Prefix + Alt-o` | Toggle logging |
| `Prefix + Alt-p` | Screen capture |
| `Prefix + Alt-i` | Full history capture |
| `Prefix + Alt-c` | Clear pane history |

### psmux-sidebar
| Key | Action |
|-----|--------|
| `Prefix + Tab` | Toggle sidebar |
| `Prefix + Shift-Tab` | Toggle (focus sidebar) |

### psmux-battery / psmux-cpu
| Key | Action |
|-----|--------|
| `Prefix + B` | Show battery info |
| `Prefix + Ctrl-c` | Show CPU/memory info |

---

## For Plugin Developers

See the [Plugin Developer Guide](PLUGIN_DEVELOPER_GUIDE.md) for:

- How to create psmux plugins from scratch
- How to port existing tmux plugins to psmux
- Complete bash-to-PowerShell translation reference
- Plugin API reference and best practices
- Testing and publishing guide

---

## Architecture

```
~/.psmux/plugins/
  ppm/                     # Plugin manager
    ppm.ps1                # Main entry point
    scripts/
      install_plugins.ps1
      update_plugins.ps1
      clean_plugins.ps1
  psmux-sensible/          # Each plugin gets its own directory
    psmux-sensible.ps1
  psmux-yank/
    psmux-yank.ps1
    scripts/
      copy_to_clipboard.ps1
  ...
```

### How It Works

1. `~/.psmux.conf` declares plugins with `set -g @plugin 'owner/repo'`
2. The final `run '..ppm.ps1'` line loads PPM
3. PPM sources all installed plugins on startup
4. Each plugin configures psmux via CLI commands (`set-option`, `bind-key`, `set-hook`)
5. `Prefix + I` clones new plugins from GitHub

### Why PowerShell?

psmux is a native Windows application. Its plugins use PowerShell because:

- **Native integration**: `Set-Clipboard`, `Get-CimInstance`, Windows APIs
- **No dependencies**: PowerShell 7 comes with psmux, no bash/cygwin needed
- **Same power**: PowerShell can do everything bash scripts do
- **Windows-first**: File paths, process management, scheduled tasks all just work

---

## License

MIT
