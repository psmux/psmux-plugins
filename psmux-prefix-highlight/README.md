# psmux-prefix-highlight

Visual indicator when prefix key is pressed. Port of [tmux-prefix-highlight](https://github.com/tmux-plugins/tmux-prefix-highlight).

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-prefix-highlight'
```

## What It Shows

| State | Indicator | Default Color |
|-------|-----------|---------------|
| Prefix pressed | `Wait` | Blue |
| Copy mode | `Copy` | Yellow |
| Sync panes | `Sync` | Red |

## Options

```tmux
# Colors
set -g @prefix_highlight_fg 'white'
set -g @prefix_highlight_bg 'blue'

# Prompt text
set -g @prefix_highlight_prefix_prompt 'Wait'
set -g @prefix_highlight_copy_prompt 'Copy'
set -g @prefix_highlight_sync_prompt 'Sync'

# Toggle indicators
set -g @prefix_highlight_show_copy_mode 'on'
set -g @prefix_highlight_show_sync_mode 'on'
```

## License

MIT
