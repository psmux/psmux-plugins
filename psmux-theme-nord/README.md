# psmux-theme-nord

An arctic, north-bluish clean and elegant theme for psmux based on the [Nord](https://nordtheme.com) color palette. Port of [arcticicestudio/nord-tmux](https://github.com/arcticicestudio/nord-tmux).

## Installation

Add to your `~/.psmux.conf`:

```tmux
# Optional: customize before loading
set -g @nord-show-powerline 'on'
set -g @nord-powerline-style 'arrow'

# Load theme
run-shell 'pwsh -NoProfile -File "/path/to/psmux-theme-nord/psmux-theme-nord.ps1"'
```

Or with PPM:

```tmux
set -g @plugin 'psmux-plugins/psmux-theme-nord'
```

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `@nord-show-powerline` | `on` / `off` | `on` | Use powerline separators |
| `@nord-powerline-style` | `arrow` / `round` | `arrow` | Arrow (``) or round (``) separator glyphs |

## Color Palette

Nord organizes its 16 colors into four groups:

### Polar Night (backgrounds)

| Name | Hex | Role |
|------|-----|------|
| nord0 | `#2e3440` | Darkest background |
| nord1 | `#3b4252` | Status bar background |
| nord2 | `#434c5e` | Highlights, message bg |
| nord3 | `#4c566a` | Inactive tab background |

### Snow Storm (foregrounds)

| Name | Hex | Role |
|------|-----|------|
| nord4 | `#d8dee9` | Primary foreground |
| nord5 | `#e5e9f0` | Brighter text |
| nord6 | `#eceff4` | Brightest / bold text |

### Frost (accents)

| Name | Hex | Role |
|------|-----|------|
| nord7 | `#8fbcbb` | Teal |
| nord8 | `#88c0d0` | Active window / pane border |
| nord9 | `#81a1c1` | Session label background |
| nord10 | `#5e81ac` | Date segment |

### Aurora (alerts)

| Name | Hex | Role |
|------|-----|------|
| nord11 | `#bf616a` | Red |
| nord12 | `#d08770` | Orange |
| nord13 | `#ebcb8b` | Yellow / prefix indicator |
| nord14 | `#a3be8c` | Green |
| nord15 | `#b48ead` | Purple |

## What It Styles

- **Status bar** — nord1 background with frost-blue session label and date segments
- **Window tabs** — inactive on nord3, active on nord8 (light blue) with bold text
- **Pane borders** — active border highlighted in nord8
- **Prefix indicator** — yellow (nord13) "WAIT" badge when prefix is active
- **Copy mode** — nord9 blue highlight
- **Messages** — styled on nord2 background

## License

MIT
