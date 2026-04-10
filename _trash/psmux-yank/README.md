# psmux-yank

Windows clipboard integration for [psmux](https://github.com/psmux/psmux). Port of [tmux-yank](https://github.com/tmux-plugins/tmux-yank).

Uses native Windows clipboard APIs -- no external tools needed.

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-yank'
```

## Key Bindings

### Copy Mode (vi)
| Key | Action |
|-----|--------|
| `y` | Copy selection to clipboard |
| `Enter` | Copy selection to clipboard (exit copy mode) |
| `Y` | Copy entire line to clipboard |
| `D` | Copy to end of line |

### Normal Mode
| Key | Action |
|-----|--------|
| `Prefix + y` | Copy visible pane content to clipboard |
| `Prefix + Y` | Copy pane working directory to clipboard |

## Options

```tmux
# Mouse drag-select copies to clipboard automatically (psmux default)
set -g @yank_with_mouse 'on'
```

## How It Works

Uses PowerShell's `Set-Clipboard` / `Get-Clipboard` cmdlets for native Windows clipboard access. No need for `xclip`, `pbcopy`, or any external utility.

## Differences from tmux-yank

| Feature | tmux-yank | psmux-yank |
|---------|-----------|------------|
| Clipboard tool | xclip/pbcopy/wl-copy | PowerShell Set-Clipboard |
| Platform | Linux/macOS | Windows |
| Dependencies | External tools | None (built-in) |
| Mouse select | Via plugin | psmux native feature |

## License

MIT
