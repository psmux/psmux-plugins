# psmux-theme-kanagawa

> A dark theme inspired by the famous painting "The Great Wave off Kanagawa" by Katsushika Hokusai.

Brings the distinctive wave/dragon/lotus color palettes to psmux with powerline segments and Nerd Font icons.

## Variants

| Variant | Description |
|---------|-------------|
| `wave`  | Default. Deep blue ocean tones with crystal highlights |
| `dragon`| Darker, muted variant with warmer earth tones |
| `lotus` | Light variant with soft, papery background |

## Installation

```
set -g @plugin 'marlocarlo/psmux-plugins/psmux-theme-kanagawa'
```

## Options

```bash
set -g @kanagawa-variant 'wave'          # wave|dragon|lotus
set -g @kanagawa-show-powerline 'on'     # powerline arrows
set -g @kanagawa-separator 'arrow'       # arrow|rounded|slant
set -g @kanagawa-show-icons 'on'         # nerd font icons
set -g @kanagawa-show-user 'on'          # username in left segment
```

## Requirements

- A [Nerd Font](https://www.nerdfonts.com/) for icon support
- psmux with true color support

## License

MIT
