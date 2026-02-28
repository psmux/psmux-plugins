# psmux-theme-everforest

> Comfortable & Pleasant Color Scheme for psmux, inspired by nature.

A warm green-toned theme designed for long coding sessions. Features powerline segments, Nerd Font icons, and multiple contrast levels.

## Variants & Contrast

| Variant | Contrast | Description |
|---------|----------|-------------|
| `dark`  | `soft`   | Slightly lighter dark background |
| `dark`  | `medium` | **Default** - balanced dark theme |
| `dark`  | `hard`   | Deepest dark background |
| `light` | `soft`   | Slightly warmer light background |
| `light` | `medium` | Standard light theme |
| `light` | `hard`   | Brightest light background |

## Installation

```
set -g @plugin 'marlocarlo/psmux-plugins/psmux-theme-everforest'
```

## Options

```bash
set -g @everforest-variant 'dark'         # dark|light
set -g @everforest-contrast 'medium'      # soft|medium|hard
set -g @everforest-show-powerline 'on'
set -g @everforest-separator 'arrow'      # arrow|rounded|slant
set -g @everforest-show-icons 'on'
set -g @everforest-show-user 'on'
```

## License

MIT
