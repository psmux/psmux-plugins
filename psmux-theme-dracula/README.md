# psmux-theme-dracula

A dark theme based on the [Dracula](https://draculatheme.com) color palette for psmux. Port of [dracula/tmux](https://github.com/dracula/tmux).

## Installation

Add to your `~/.psmux.conf`:

```tmux
# Optional: customize before loading
set -g @dracula-show-powerline 'on'
set -g @dracula-show-left-icon 'session'
set -g @dracula-border-contrast 'off'
set -g @dracula-show-flags 'on'

# Load theme
run-shell 'pwsh -NoProfile -File "/path/to/psmux-theme-dracula/psmux-theme-dracula.ps1"'
```

Or with PPM:

```tmux
set -g @plugin 'psmux-plugins/psmux-theme-dracula'
```

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `@dracula-show-powerline` | `on` / `off` | `on` | Use powerline arrow separators |
| `@dracula-show-left-icon` | `session` / `window` / custom string | `session` | Content shown in the left status segment |
| `@dracula-border-contrast` | `on` / `off` | `off` | High-contrast pane borders |
| `@dracula-show-flags` | `on` / `off` | `on` | Display window flags (e.g. `*`, `-`, `Z`) |

## Color Palette

| Color | Hex |
|-------|-----|
| Background | `#282a36` |
| Current Line | `#44475a` |
| Foreground | `#f8f8f2` |
| Comment | `#6272a4` |
| Cyan | `#8be9fd` |
| Green | `#50fa7b` |
| Orange | `#ffb86c` |
| Pink | `#ff79c6` |
| Purple | `#bd93f9` |
| Red | `#ff5555` |
| Yellow | `#f1fa8c` |

## What It Styles

- **Status bar** — dark background with green session label and purple date segment
- **Window tabs** — inactive on current-line gray, active on purple with bold text
- **Pane borders** — active border highlighted in purple
- **Prefix indicator** — yellow "WAIT" badge when prefix is active
- **Copy mode** — purple highlight
- **Messages** — styled on current-line background

## License

MIT
