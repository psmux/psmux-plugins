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

- All sessions (idempotent: existing sessions are skipped)
- Windows with correct names
- Panes in correct working directories
- Exact layout geometry via `select-layout` replay
- Active pane selection per window
- Zoomed pane state
- Pane titles
- Running processes from the restore list (configurable)
- Active window selection per session

## Options

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
```

## Save File Format

Saves are stored as JSON files with timestamps. The `last` file always points to the most recent save. A maximum of 20 backups are kept; older files are automatically pruned.

Duplicate saves are skipped when the environment has not changed.

```
~/.psmux/resurrect/
  psmux_resurrect_20260225_143022.json
  psmux_resurrect_20260225_150000.json
  last
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
| Vim/Neovim strategy | Special Session.vim handling | Process restore via command match |
| Grouped sessions | Yes | Not applicable (Windows) |
| Hooks | 4 hook points | Planned |

## License

MIT
