# psmux-resurrect

Save and restore psmux sessions across reboots. Port of [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect).

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-resurrect'
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Prefix + Ctrl-s` | Save environment |
| `Prefix + Ctrl-r` | Restore environment |

## What Gets Saved

- All sessions and their names
- All windows and their names
- Exact pane layouts (horizontal + vertical splits with sizes)
- Working directories for each pane
- Active window per session
- Active pane per window
- Zoomed pane state
- Pane titles
- Running process commands (for process restore)
- Window flags
- Pane contents (optional)

## What Gets Restored

- All sessions (idempotent by default: a session that is still running is kept, and only the saved windows it is missing are added to it; see `@resurrect-overwrite` below)
- Windows with correct names
- Panes in correct working directories
- Exact layout geometry via `select-layout` replay
- Active pane selection per window
- Zoomed pane state
- Pane titles
- Running processes from the restore list (configurable)
- Active window selection per session

## Options

Set these in `~/.psmux.conf`. psmux runs one server process per session, so a
`set -g` typed at runtime only reaches the session it targets, while the config
file is applied to every session as it starts.

```tmux
# Custom save directory (default: ~/.psmux/resurrect)
set -g @resurrect-dir '~/.psmux/resurrect'

# Save pane contents
set -g @resurrect-capture-pane-contents 'on'

# Restore additional processes (space separated)
# Default list: python python3 node npm ssh wsl htop vim nvim less more tail
set -g @resurrect-processes 'ssh python node'

# Disable process restore entirely
set -g @resurrect-processes 'false'

# Restore ALL processes (use with caution)
set -g @resurrect-processes ':all:'

# Use tilde for fuzzy matching (restore if command contains the string)
set -g @resurrect-processes '"~rails server" "~npm start"'

# Overwrite sessions that are already running instead of keeping them.
# Default is off: a running session is kept, its existing windows are not
# touched, and saved windows it no longer has (matched by window index, as
# tmux-resurrect does) are added to it. When 'on', the running session is
# killed and fully recreated from the save.
set -g @resurrect-overwrite 'on'

# What to do with auto-named sessions (the 0, 1, 2 a bare `psmux` creates).
#   auto  (default) save one only once you have shaped it: a second window
#         or pane, or a program other than an idle shell in its pane
#   on    save every auto-named session (tmux-resurrect behaviour)
#   off   never save auto-named sessions
set -g @resurrect-save-unnamed 'auto'
```

### Unnamed sessions

A bare `psmux` names its session with the next free number. Saving those
unconditionally makes them permanent: restore recreates them, the next save
persists them again, and deleting them from the save files does not help
because the next auto-save writes them straight back. With the default `auto`
policy an untouched numbered session (one window, one pane, nothing but an
idle shell) is left out of the save, since the next bare launch gives you
exactly that anyway. As soon as you split it, open a second window, or start a
program from the restore list in it, it is saved like any named session.

Sessions whose names start with `__` are internal to psmux and are never
saved.

## Restore Progress Indicator

During restore, the plugin writes per-session progress into the
`@resurrect-status` user option (and a no-fade `display-message -d 0` toast).
Add `#{@resurrect-status}` to your `status-right` to see a persistent progress
bar that updates per session instead of relying on the toast alone:

```tmux
set -g status-right '#{@resurrect-status} | %H:%M'
```

While restoring:

```
psmux-resurrect: restoring [######--------] 3/7  devbox
```

On completion the status briefly shows a summary, then clears:

```
psmux-resurrect: restored 7 sessions, 23 windows in 3.1s
```

Sessions that were still running are reported too. One that already had
every saved window is left alone; one that was missing windows gets them
added:

```
psmux-resurrect: nothing to restore, all 12 saved sessions are still running (psmux ls to see them, @resurrect-overwrite 'on' to recreate)
psmux-resurrect: restored 2/12, added 3 windows to 1 running, left 9 alone
```

With `@resurrect-overwrite 'on'`, sessions that were killed and recreated are
counted separately from freshly-created ones:

```
psmux-resurrect: restored 12 sessions, 34 windows in 4.2s (3 overwritten)
```

The status is cleared automatically a few seconds after restore completes.

## Restore Strategies

For programs that maintain their own session state (editors, REPLs, TUI agents
with internal session IDs), `pane_current_command` is rarely enough to restore
a meaningful workspace. Restore strategies let a per-program script compute the
actual command to send to the pane at restore time.

This is a port of [tmux-resurrect's strategies mechanism](https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/restoring_vim_and_neovim_sessions.md).

### Activate a strategy

```tmux
# Use the bundled nvim_session strategy when restoring nvim panes
set -g @resurrect-strategy-nvim 'session'
```

The general form is `@resurrect-strategy-<program> '<strategy-name>'`, where
`<program>` is the basename of `pane_current_command` (without `.exe`) and
`<strategy-name>` selects which strategy file to use.

### Lookup order

At restore time, `<program>_<strategy-name>.ps1` is searched in:

1. `~/.psmux/strategies/<program>_<strategy>.ps1` (your own strategies)
2. `<plugin>/strategies/<program>_<strategy>.ps1` (strategies shipped with the plugin)

The first existing file wins, so user strategies override bundled ones.

### Strategy contract

A strategy script receives two positional arguments and writes one line to
stdout (the command that will be sent to the restored pane):

```powershell
# ~/.psmux/strategies/<program>_<strategy>.ps1
param(
    [Parameter(Mandatory)] [string] $OriginalCommand,
    [Parameter(Mandatory)] [string] $Directory
)

# Compute the restore command, e.g. by querying tool-specific state in $Directory.
# Echo $OriginalCommand if you cannot improve on the default.
'mytool --resume <id>'
```

Strategy failures (non-zero exit, empty stdout, exceptions) silently fall back
to the original saved command, so a broken strategy never blocks a restore.

### Bundled strategies

| Strategy | Activated by | Behavior |
|----------|-----------------------------------|----------|
| `nvim_session` | `set -g @resurrect-strategy-nvim 'session'` | Restores `nvim -S` if `Session.vim` exists in the pane's directory (e.g. via [vim-obsession](https://github.com/tpope/vim-obsession)); otherwise falls back to bare `nvim`. |

## Save File Format

Saves are stored as JSON files with timestamps. The `last` file always points to the most recent save. A maximum of 20 backups are kept; older files are automatically pruned.

Duplicate saves are skipped when the environment has not changed.

```
~/.psmux/resurrect/
  psmux_resurrect_20260225_143022.json
  psmux_resurrect_20260225_150000.json
  last
```

### Troubleshooting

**Restore says everything is "still running" and nothing comes back.**
Closing the terminal window does not stop psmux: the client detaches and the
server, with every session in it, keeps running (see psmux/psmux#585). So the
sessions you saved are usually still there, and restore leaves a running
session alone by default, adding only saved windows it no longer has. Check
with:

```powershell
psmux ls                 # what is actually running
psmux attach -t <name>   # go back to one of them
```

If you really want the saved copy instead, either `psmux kill-server` and
restore into a fresh server, or set `@resurrect-overwrite 'on'` to have restore
kill and recreate matching sessions.

**Dozens of numbered sessions.** Each bare `psmux` while the server is still
running creates one more numbered session. Older plugin versions saved all of
them; `@resurrect-save-unnamed` (above) now leaves untouched ones out. To clear
out the ones that already exist: `psmux kill-server`, or
`psmux kill-session -t <n>` for each.

**Seeing what a save contains.** The `last` file under `~/.psmux/resurrect`
holds the path of the save that restore will use:

```powershell
$last = (Get-Content "$env:USERPROFILE\.psmux\resurrect\last" -Raw).Trim()
(Get-Content $last -Raw | ConvertFrom-Json).sessions | Select-Object name, @{n='windows';e={$_.windows.Count}}
```

Running the save or restore script directly from a terminal prints the same
report the key binding shows in its popup, which is the quickest way to see
what it decided and why:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.psmux\plugins\psmux-resurrect\scripts\restore.ps1"
```

### Restoring a Previous Save

1. Open `~/.psmux/resurrect/`
2. Find the save file you want (filenames have timestamps)
3. Update the `last` file to point to it: write the full path of the desired save file into `last`
4. Restore with `Prefix + Ctrl-r`

## Differences from tmux-resurrect

| Feature | tmux-resurrect | psmux-resurrect |
|---------|---------------|-----------------|
| Save format | Custom TSV text | JSON |
| Process restore | bash processes | PowerShell/cmd/python/node/ssh/wsl |
| Platform | Linux/macOS/Cygwin | Windows |
| Layout restore | select-layout replay | select-layout replay |
| Zoomed panes | Yes | Yes |
| Active pane | Yes | Yes |
| Pane titles | Yes | Yes |
| Backup rotation | 30 day expiry | Keep latest 20 |
| Save dedup | symlink diff check | JSON structural compare |
| Vim/Neovim strategy | Special Session.vim handling | Restore strategies (port; bundled `nvim_session`) |
| Grouped sessions | Yes | Not applicable (Windows) |
| Hooks | 4 hook points | Planned |

## License

MIT
