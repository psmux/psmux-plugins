# psmux-theme-catppuccin

A soothing pastel theme for psmux based on [Catppuccin](https://catppuccin.com). Port of [catppuccin/tmux](https://github.com/catppuccin/tmux).

Four flavor variants — from the warm dark **Mocha** to the light **Latte**.

## Installation

Add to your `~/.psmux.conf`:

```tmux
# Optional: customize before loading
set -g @catppuccin-flavor 'mocha'
set -g @catppuccin-show-powerline 'on'
set -g @catppuccin-window-style 'rounded'

# Load theme
run-shell 'pwsh -NoProfile -File "/path/to/psmux-theme-catppuccin/psmux-theme-catppuccin.ps1"'
```

Or with PPM:

```tmux
set -g @plugin 'psmux-plugins/psmux-theme-catppuccin'
```

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `@catppuccin-flavor` | `latte` / `frappe` / `macchiato` / `mocha` | `mocha` | Color flavor to use |
| `@catppuccin-show-powerline` | `on` / `off` | `on` | Use powerline arrow separators |
| `@catppuccin-window-style` | `rounded` / `square` / `none` | `rounded` | Separator style around window tabs |

## Color Flavors

### Mocha (dark, default)

| Role | Hex |
|------|-----|
| Base | `#1e1e2e` |
| Text | `#cdd6f4` |
| Blue | `#89b4fa` |
| Green | `#a6e3a1` |
| Mauve | `#cba6f7` |
| Peach | `#fab387` |

### Macchiato

| Role | Hex |
|------|-----|
| Base | `#24273a` |
| Text | `#cad3f5` |
| Blue | `#8aadf4` |
| Green | `#a6da95` |
| Mauve | `#c6a0f6` |
| Peach | `#f5a97f` |

### Frappé

| Role | Hex |
|------|-----|
| Base | `#303446` |
| Text | `#c6d0f5` |
| Blue | `#8caaee` |
| Green | `#a6d189` |
| Mauve | `#ca9ee6` |
| Peach | `#ef9f76` |

### Latte (light)

| Role | Hex |
|------|-----|
| Base | `#eff1f5` |
| Text | `#4c4f69` |
| Blue | `#1e66f5` |
| Green | `#40a02b` |
| Mauve | `#8839ef` |
| Peach | `#fe640b` |

## What It Styles

- **Status bar** — base-colored background with blue session label and mauve date segment
- **Window tabs** — inactive on surface, active on green with crust text; separator style configurable
- **Pane borders** — active border highlighted in blue
- **Prefix indicator** — peach "PREFIX" badge when prefix is active
- **Copy mode** — blue highlight with crust foreground
- **Messages** — styled on surface0 background

## License

MIT
