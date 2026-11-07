# psmux-theme-nord

An arctic, north-bluish clean and elegant theme for psmux based on the [Nord](https://nordtheme.com) color palette. Port of [arcticicestudio/nord-tmux](https://github.com/arcticicestudio/nord-tmux).

## Installation

With PPM:

```tmux
set -g @plugin 'psmux-plugins/psmux-theme-nord'
```

Or run the script yourself:

```tmux
run-shell 'pwsh -NoProfile -File "/path/to/psmux-theme-nord/psmux-theme-nord.ps1"'
```

Loaded through PPM, psmux first paints the theme's static look from `plugin.conf`
straight away. That look needs no Nerd Font. If you set any `@nord-*` option
below, `plugin.conf` then runs `psmux-theme-nord.ps1`, which applies the
powerline version with your options a moment after the server starts. Both
ways of loading give the same result, and the options work whether you set
them before or after the `@plugin` line.

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `@nord-show-powerline` | `on` / `off` | `on` | Use powerline separators (needs a Nerd Font) |
| `@nord-separator` | `arrow` / `rounded` / `slant` | `arrow` | Shape of the powerline separators |
| `@nord-show-icons` | `on` / `off` | `on` | Show Nerd Font icons |
| `@nord-show-user` | `on` / `off` | `on` | Show the user name on the left |
| `@nord-show-zoom` | `on` / `off` | `on` | Mark a zoomed window |
| `@nord-show-sync` | `on` / `off` | `on` | Show a SYNC badge when panes are synchronized |
| `@nord-show-pane-count` | `on` / `off` | `on` | Show the pane count on windows with more than one pane |

Example:

```tmux
set -g @nord-separator 'rounded'
set -g @nord-show-user 'off'
set -g @plugin 'psmux-plugins/psmux-theme-nord'
```
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
