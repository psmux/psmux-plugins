# psmux-sidebar

Directory tree sidebar for [psmux](https://github.com/psmux/psmux). Port of [tmux-sidebar](https://github.com/tmux-plugins/tmux-sidebar).

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-sidebar'
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Prefix + Tab` | Toggle sidebar (keep focus on main pane) |
| `Prefix + Shift-Tab` | Toggle sidebar (focus on sidebar) |

## Options

```tmux
# Sidebar width (default: 40)
set -g @sidebar-width '40'

# Sidebar position (default: left)
set -g @sidebar-position 'left'  # or 'right'

# Custom tree command
set -g @sidebar-tree-command 'tree /F /A'
```

## How It Works

Opens a split pane running `tree` (or PowerShell `Get-ChildItem` fallback) showing the current pane's working directory. Press the binding again to close.

## License

MIT
