# psmux-cpu

CPU and memory usage in the psmux status bar. Port of [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu).

Uses native Windows CIM/WMI -- no external tools needed.

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-cpu'
```

## Usage

Add `{cpu}` and/or `{ram}` to your status-right:

```tmux
set -g status-right '{cpu} {ram} | %H:%M'
```

Or press `Prefix + Ctrl-c` for detailed system info.

## Color Coding

### CPU
| Level | Color |
|-------|-------|
| < 30% | Green |
| 30-80% | Yellow |
| > 80% | Red |

### Memory
| Level | Color |
|-------|-------|
| < 50% | Green |
| 50-80% | Yellow |
| > 80% | Red |

## Stored Variables

Available as `@` options after loading:

| Variable | Example |
|----------|---------|
| `@cpu_percentage` | `45%` |
| `@ram_percentage` | `62%` |
| `@ram_used` | `10.2G` |
| `@ram_total` | `16.0G` |

## License

MIT
