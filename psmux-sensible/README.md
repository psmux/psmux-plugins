# psmux-sensible

Sensible default settings for [psmux](https://github.com/marlocarlo/psmux). Port of [tmux-sensible](https://github.com/tmux-plugins/tmux-sensible).

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-sensible'
```

## What it sets

| Option | Value | Why |
|--------|-------|-----|
| `escape-time` | 50 | Faster key response |
| `history-limit` | 50000 | More scrollback |
| `mouse` | on | Mouse support enabled |
| `mode-keys` | vi | Vi copy-mode keys |
| `focus-events` | on | Vim/Neovim focus detection |
| `display-time` | 2000 | Readable messages |
| `status-interval` | 5 | Frequent status updates |
| `base-index` | 1 | Windows start at 1 |
| `pane-base-index` | 1 | Panes start at 1 |
| `renumber-windows` | on | No gaps after close |
| `automatic-rename` | on | Dynamic window names |

## Key Bindings

| Key | Action |
|-----|--------|
| `Prefix + R` | Reload config |
| `Prefix + \|` | Split horizontal |
| `Prefix + -` | Split vertical |
| `Shift + Left/Right` | Previous/next window (no prefix) |

## Override

Set your own values AFTER loading the plugin in `~/.psmux.conf`.

## License

MIT
