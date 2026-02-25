# psmux-theme-gruvbox

A retro groove color scheme with warm, earthy tones for psmux based on [Gruvbox](https://github.com/morhetz/gruvbox). Port of [egel/tmux-gruvbox](https://github.com/egel/tmux-gruvbox).

Supports **dark** and **light** variants, each with three contrast levels.

## Installation

Add to your `~/.psmux.conf`:

```tmux
# Optional: customize before loading
set -g @gruvbox-variant 'dark'
set -g @gruvbox-contrast 'medium'
set -g @gruvbox-show-powerline 'on'

# Load theme
run-shell 'pwsh -NoProfile -File "/path/to/psmux-theme-gruvbox/psmux-theme-gruvbox.ps1"'
```

Or with PPM:

```tmux
set -g @plugin 'psmux-plugins/psmux-theme-gruvbox'
```

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `@gruvbox-variant` | `dark` / `light` | `dark` | Dark or light background variant |
| `@gruvbox-contrast` | `soft` / `medium` / `hard` | `medium` | Background contrast level |
| `@gruvbox-show-powerline` | `on` / `off` | `on` | Use powerline arrow separators |

## Color Palette

### Dark variant

| Contrast | Background Hex |
|----------|---------------|
| Soft | `#32302f` |
| Medium | `#282828` |
| Hard | `#1d2021` |

| Role | Hex |
|------|-----|
| Foreground | `#ebdbb2` |
| Red | `#fb4934` |
| Green | `#b8bb26` |
| Yellow | `#fabd2f` |
| Blue | `#83a598` |
| Purple | `#d3869b` |
| Aqua | `#8ec07c` |
| Orange | `#fe8019` |
| Gray | `#928374` |

### Light variant

| Role | Hex |
|------|-----|
| Background | `#fbf1c7` |
| Foreground | `#3c3836` |
| Red | `#9d0006` |
| Green | `#79740e` |
| Yellow | `#b57614` |
| Blue | `#076678` |
| Purple | `#8f3f71` |
| Aqua | `#427b58` |
| Orange | `#af3a03` |

## What It Styles

- **Status bar** — bg1 background with yellow session label and aqua date segment
- **Window tabs** — inactive on bg2, active on green with bold dark text
- **Pane borders** — active border highlighted in aqua
- **Prefix indicator** — orange "WAIT" badge when prefix is active
- **Copy mode** — yellow highlight with dark foreground
- **Messages** — styled on bg2 background

## License

MIT
