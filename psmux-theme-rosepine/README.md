# psmux-theme-rosepine

> Soho vibes for psmux — all natural pine, faux fur and a bit of soho.

A [Rosé Pine](https://rosepinetheme.com) theme for psmux with powerline segments, Nerd Font icons, and multiple separator styles.

## Preview

```
 ❐ main │╭ 1  pwsh ╮╭ 2  nvim ╮│                  12:30   Mon   28-Feb
```

## Variants

| Variant | Description |
|---------|-------------|
| `main`  | Default dark theme with muted purple and rose tones |
| `moon`  | Darker variant with cooler undertones |
| `dawn`  | Light variant with warm, paper-like background |

## Installation

Add to your `~/.psmux.conf`:

```
set -g @plugin 'psmux-plugins/psmux-theme-rosepine'
```

## Options

```bash
# Choose variant (main/moon/dawn)
set -g @rosepine-variant 'main'

# Enable powerline separators
set -g @rosepine-show-powerline 'on'

# Separator style: arrow, rounded, or slant
set -g @rosepine-separator 'arrow'

# Enable Nerd Font icons
set -g @rosepine-show-icons 'on'

# Left section icon: session, window, or rocket
set -g @rosepine-left-icon 'session'

# Show username in status left
set -g @rosepine-show-user 'on'
```

## Requirements

- A [Nerd Font](https://www.nerdfonts.com/) for icon support (recommended: FiraCode Nerd Font)
- psmux with true color support

## License

MIT
