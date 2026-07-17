# psmux-theme-warm-burnout

A minimal warm color theme for psmux based on [felipefdl/warm-burnout](https://github.com/felipefdl/warm-burnout).

Supports the original **dark** and **light** variants.

## Installation

Default repo-style install via PPM or `source-file`:

```tmux
set -g @plugin 'psmux-plugins/psmux-theme-warm-burnout'
```

`plugin.conf` follows the same convention as the other theme plugins in this repo and applies the default **dark** variant.

To load a specific variant, run the PowerShell entry point directly:

```tmux
set -g @warm-burnout-variant 'light'   # dark|light
run-shell 'pwsh -NoProfile -File "/path/to/psmux-theme-warm-burnout/psmux-theme-warm-burnout.ps1"'
```

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `@warm-burnout-variant` | `dark` / `light` | `dark` | Selects the palette when loading the `.ps1` entry point |

## What It Styles

- Status bar and session label
- Window list and active window highlight
- Pane borders
- Messages and command prompt
- Copy mode highlight
- Clock mode color

## License

MIT