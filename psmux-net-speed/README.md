# psmux-net-speed

> Network bandwidth monitor for psmux status bar.

Shows real-time upload and download speeds with Nerd Font icons.

## Preview

```
 󰇚 1.2M 󰕒 256K
```

## Installation

```
set -g @plugin 'psmux/psmux-plugins/psmux-net-speed'
```

## Usage

Add `#{@net_speed_display}` to your status-right:

```bash
set -g status-right '#{@net_speed_display} | %H:%M'
```

Or access individual values:
- `#{@net_speed_display}` - Combined download/upload display
- `#{@net_speed_down}` - Download speed only  
- `#{@net_speed_up}` - Upload speed only

## Keybindings

| Key | Action |
|-----|--------|
| `Prefix + C-n` | Show detailed network info |

## Requirements

- Windows with active network adapter
- A [Nerd Font](https://www.nerdfonts.com/) for icons

## License

MIT
