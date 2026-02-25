# psmux-battery

Battery status in the psmux status bar. Port of [tmux-battery](https://github.com/tmux-plugins/tmux-battery).

Uses native Windows CIM (WMI) -- no external tools needed.

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-battery'
```

## Usage

Add `{battery}` to your status-right:

```tmux
set -g status-right '{battery} | %H:%M %d-%b-%y'
```

Or press `Prefix + B` to see battery info as a message.

## Color Coding

| Level | Color |
|-------|-------|
| > 50% | Green |
| 20-50% | Yellow |
| < 20% | Red |

## Status Icons

| Status | Icon |
|--------|------|
| Charging | `+` |
| Charged | `=` |
| Discharging | `-` |

## How It Works

Polls `Win32_Battery` via CIM on client-attached hook and status refreshes. Desktops without batteries show "AC".

## License

MIT
