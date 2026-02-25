# psmux-theme-tokyonight

A clean dark theme for psmux inspired by the [Tokyo Night](https://github.com/folke/tokyonight.nvim) color scheme. Port of [janoamaral/tokyo-night-tmux](https://github.com/janoamaral/tokyo-night-tmux).

Three style variants: **Night**, **Storm**, and **Moon**.

## Installation

Add to your `~/.psmux.conf`:

```tmux
# Optional: customize before loading
set -g @tokyonight-style 'night'
set -g @tokyonight-show-powerline 'on'

# Load theme
run-shell 'pwsh -NoProfile -File "/path/to/psmux-theme-tokyonight/psmux-theme-tokyonight.ps1"'
```

Or with PPM:

```tmux
set -g @plugin 'psmux-plugins/psmux-theme-tokyonight'
```

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `@tokyonight-style` | `night` / `storm` / `moon` | `night` | Color style variant |
| `@tokyonight-show-powerline` | `on` / `off` | `on` | Use powerline arrow separators |

## Color Styles

### Night (default)

| Role | Hex |
|------|-----|
| Background | `#1a1b26` |
| Foreground | `#c0caf5` |
| Blue | `#7aa2f7` |
| Cyan | `#7dcfff` |
| Green | `#9ece6a` |
| Magenta | `#bb9af7` |
| Red | `#f7768e` |
| Yellow | `#e0af68` |
| Orange | `#ff9e64` |

### Storm

| Role | Hex |
|------|-----|
| Background | `#24283b` |
| Foreground | `#c0caf5` |
| Blue | `#7aa2f7` |
| Magenta | `#bb9af7` |

Same accent colors as Night with a slightly lighter background.

### Moon

| Role | Hex |
|------|-----|
| Background | `#222436` |
| Foreground | `#c8d3f5` |
| Blue | `#82aaff` |
| Cyan | `#86e1fc` |
| Green | `#c3e88d` |
| Magenta | `#c099ff` |
| Red | `#ff757f` |
| Yellow | `#ffc777` |

Warmer accent palette with distinct hues.

## What It Styles

- **Status bar** — dark background with blue session label and magenta date segment
- **Window tabs** — inactive on highlight background with muted comment text, active on cyan with bold dark text
- **Pane borders** — active border highlighted in blue
- **Prefix indicator** — orange badge when prefix is active
- **Copy mode** — blue highlight with dark foreground
- **Messages** — styled on highlight background

## License

MIT
