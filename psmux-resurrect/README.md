# psmux-resurrect

Save and restore psmux sessions across reboots. Port of [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect).

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-resurrect'
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Prefix + Ctrl-s` | Save environment |
| `Prefix + Ctrl-r` | Restore environment |

## What Gets Saved

- All sessions and their names
- All windows and their names
- Pane layouts
- Working directories for each pane
- Active window selection
- Pane contents (optional)

## Options

```tmux
# Custom save directory (default: ~/.psmux/resurrect)
set -g @resurrect-dir '~/.psmux/resurrect'

# Save pane contents
set -g @resurrect-capture-pane-contents 'on'
```

## Save File Format

Saves are stored as JSON files with timestamps. The `last` file always points to the most recent save.

```
~/.psmux/resurrect/
  psmux_resurrect_20260225_143022.json
  last
```

## Differences from tmux-resurrect

| Feature | tmux-resurrect | psmux-resurrect |
|---------|---------------|-----------------|
| Save format | Custom text | JSON |
| Process restore | bash processes | PowerShell/cmd |
| Platform | Linux/macOS | Windows |
| Vim strategy | Special handling | N/A |

## License

MIT
