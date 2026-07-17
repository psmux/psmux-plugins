# PPM - Psmux Plugin Manager

The plugin manager for [psmux](https://github.com/psmux/psmux). Inspired by [tpm](https://github.com/tmux-plugins/tpm) for tmux.

## Installation

```powershell
git clone https://github.com/psmux/psmux-plugins.git "$env:TEMP\psmux-plugins" ; Copy-Item "$env:TEMP\psmux-plugins\ppm" "$env:USERPROFILE\.psmux\plugins\ppm" -Recurse ; Remove-Item "$env:TEMP\psmux-plugins" -Recurse -Force
```

## Configuration

Add to your `~/.psmux.conf`:

```tmux
# List of plugins
set -g @plugin 'psmux-plugins/ppm'
set -g @plugin 'psmux-plugins/psmux-sensible'

# Initialize PPM (keep this line at the very bottom of .psmux.conf)
run '~/.psmux/plugins/ppm/ppm.ps1'
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Prefix + I` | Install declared plugins |
| `Prefix + U` | Update all plugins |
| `Prefix + M` | Remove unused plugins |

## Plugin Format

```tmux
set -g @plugin 'psmux-plugins/psmux-sensible'                        # GitHub shorthand: owner/repo
set -g @plugin 'someone/their-plugin'                                 # GitHub shorthand: owner/repo
set -g @plugin 'https://gitlab.com/user/plugin.git'                   # Any git URL
set -g @plugin 'someone/their-monorepo/some-plugin'                   # 3-segment: owner/repo/subdir
set -g @plugin 'someone/their-plugin#feature-branch'                  # #branch suffix
set -g @plugin 'someone/their-monorepo/some-plugin#feature-branch'    # 3-segment + #branch combined
```

### Resolution order

A spec is first split on `#` into `(base, branch)`. If `branch` is present, it is passed as `git clone --branch <branch>` to whichever clone the resolved `base` triggers below.

| Form | Behavior |
|---|---|
| `https://...` / `git@...` | Clone the URL directly. |
| `owner/repo/subdir` (3 segments) | Clone `github.com/owner/repo.git` and extract `subdir`. No probe, no `MONOREPO_MAP` involvement, works for any owner. |
| `owner/repo` (2 segments), `owner` in `MONOREPO_MAP` | Clone the mapped monorepo directly and extract `repo`. No probe (added to close a guaranteed 404 request per install and a squatting vector, see [#25](https://github.com/psmux/psmux-plugins/issues/25) and [#16](https://github.com/psmux/psmux-plugins/issues/16)). |
| `owner/repo` (2 segments), `owner` not in `MONOREPO_MAP` | Try `github.com/owner/repo.git` directly; on failure, fall back through `MONOREPO_MAP` if `owner` ends up matching one after all. |
| Bare name | Treated as `psmux-plugins/<name>`, which resolves via the `MONOREPO_MAP` row above. |

`psmux-plugins/<name>` is shorthand for the monorepo mapping baked into ppm (currently `psmux/psmux-plugins`); the 3-segment form lets you address *any* owner's monorepo without editing `ppm.ps1`, e.g. to install from your own fork or a feature branch:

```tmux
set -g @plugin 'your-github-user/psmux-plugins/psmux-continuum#your-fix-branch'
```

Every git clone ppm runs (probe, monorepo, or direct) disables interactive credential prompts, so a missing repo or branch fails fast with a clean error instead of ever popping a GitHub sign-in window.

## How It Works

1. PPM reads `@plugin` declarations from your config
2. `Prefix + I` clones plugins to `~/.psmux/plugins/`
3. On startup, PPM sources each installed plugin's entry point
4. Plugin entry points: `<name>.ps1`, `plugin.ps1`, `init.ps1`, or `.conf` files

## License

MIT
