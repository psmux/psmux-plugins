# psmux-pain-control

Better pane navigation and management for [psmux](https://github.com/psmux/psmux). Port of [tmux-pain-control](https://github.com/tmux-plugins/tmux-pain-control).

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-pain-control'
```

## Key Bindings

### Pane Navigation (vim-style)
| Key | Action |
|-----|--------|
| `Prefix + h` | Select pane left |
| `Prefix + j` | Select pane down |
| `Prefix + k` | Select pane up |
| `Prefix + l` | Select pane right |

### Pane Resizing (repeatable)
| Key | Action |
|-----|--------|
| `Prefix + H` | Resize left |
| `Prefix + J` | Resize down |
| `Prefix + K` | Resize up |
| `Prefix + L` | Resize right |

### Pane Splitting (inherit directory)
| Key | Action |
|-----|--------|
| `Prefix + \|` | Split horizontal (side by side) |
| `Prefix + \` | Split horizontal (side by side) |
| `Prefix + -` | Split vertical (top/bottom) |
| `Prefix + _` | Split vertical (top/bottom) |

### Window Management
| Key | Action |
|-----|--------|
| `Prefix + <` | Swap window left |
| `Prefix + >` | Swap window right |
| `Prefix + c` | New window (inherit directory) |

## Options

```tmux
# Resize step (default: 5)
set -g @pane_resize '10'
```

## License

MIT
