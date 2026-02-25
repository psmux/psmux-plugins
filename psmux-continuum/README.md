# psmux-continuum

Automatic save/restore for psmux sessions. Port of [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum).

Requires **psmux-resurrect**.

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-resurrect'
set -g @plugin 'psmux-plugins/psmux-continuum'
```

## Features

- Auto-saves environment every 15 minutes (configurable)
- Optionally restores environment on psmux server start
- Optionally starts psmux on Windows login (Scheduled Task)

## Options

```tmux
# Save interval in minutes (default: 15, set to 0 to disable)
set -g @continuum-save-interval '15'

# Auto-restore when psmux server starts
set -g @continuum-restore 'on'

# Auto-start psmux on Windows login
set -g @continuum-boot 'on'
```

## How It Works

- Uses a PowerShell background job to periodically call psmux-resurrect's save
- On server start, checks for the last save file and restores if enabled
- Boot feature uses Windows Scheduled Tasks (no registry hacking)

## License

MIT
