# psmux-logging

Log pane output to files. Port of [tmux-logging](https://github.com/tmux-plugins/tmux-logging).

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-logging'
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Prefix + P` | Toggle logging (start/stop) |
| `Prefix + Alt-p` | Save visible screen ("screenshot") |
| `Prefix + Alt-P` | Save complete pane history |
| `Prefix + Alt-c` | Clear pane history |

## Log Location

Default: `~/.psmux/logs/`

Files are named: `psmux-{session}-w{window}-p{pane}-{timestamp}.log`

## Options

```tmux
set -g @logging-path '~/.psmux/logs'
```

## Use Cases

- Debug long-running scripts
- Audit terminal sessions
- Capture build output
- Record SSH sessions

## License

MIT
