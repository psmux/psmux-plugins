# PPM - Psmux Plugin Manager

The plugin manager for [psmux](https://github.com/psmux/psmux). Inspired by [tpm](https://github.com/tmux-plugins/tpm) for tmux.

## Installation

```powershell
git clone https://github.com/psmux/psmux-plugins.git "$env:TEMP\psmux-plugins" ; Copy-Item "$env:TEMP\psmux-plugins\ppm" "$env:USERPROFILE\.psmux\plugins\ppm" -Recurse ; Remove-Item "$env:TEMP\psmux-plugins" -Recurse -Force
```

## Configuration

Add to your `~/.psmux.conf`:

```tmux
# List of plugins
set -g @plugin 'psmux-plugins/ppm'
set -g @plugin 'psmux-plugins/psmux-sensible'

# Initialize PPM (keep this line at the very bottom of .psmux.conf)
run '~/.psmux/plugins/ppm/ppm.ps1'
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Prefix + I` | Install declared plugins |
| `Prefix + U` | Update all plugins |
| `Prefix + M` | Remove unused plugins |

## Plugin Format

Plugins are specified as `owner/repo` (GitHub shorthand) or full git URLs:

```tmux
set -g @plugin 'psmux-plugins/psmux-sensible'      # GitHub: psmux-plugins/psmux-sensible
set -g @plugin 'someone/their-plugin'               # GitHub: someone/their-plugin
set -g @plugin 'https://gitlab.com/user/plugin.git' # Any git URL
```

## How It Works

1. PPM reads `@plugin` declarations from your config
2. `Prefix + I` clones plugins to `~/.psmux/plugins/`
3. On startup, PPM sources each installed plugin's entry point
4. Plugin entry points: `<name>.ps1`, `plugin.ps1`, `init.ps1`, or `.conf` files

## License

MIT
