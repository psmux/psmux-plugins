# psmux-git-status

> Git branch and status indicators in your psmux status bar.

The must-have plugin for developers. Shows branch name, dirty/clean status, staged/modified/untracked counts, ahead/behind upstream, and stash count — all with Nerd Font icons.

## Preview

```
  main ✓                    # clean repo
  develop 󰐕2 3 1       # 2 staged, 3 modified, 1 untracked
  feature/x ⇡3 ⇣1 󰆓2      # 3 ahead, 1 behind, 2 stashes
```

## Icons

| Icon | Meaning |
|------|---------|
|  | Branch |
| 󰜘 | Detached HEAD |
| 󰐕 | Staged changes |
|  | Modified files |
|  | Untracked files |
|  | Merge conflicts |
| ⇡ | Commits ahead |
| ⇣ | Commits behind |
| 󰆓 | Stash entries |
| ✓ | Clean working tree |

## Installation

```
set -g @plugin 'psmux-plugins/psmux-git-status'
```

## Usage

Add `#{git_status}` to your status-right or status-left:

```bash
set -g status-right '#{git_status} | %H:%M'
```

## Keybindings

| Key | Action |
|-----|--------|
| `Prefix + C-g` | Show detailed git info (branch, last commit, changed files) |

## Requirements

- `git` in PATH
- A [Nerd Font](https://www.nerdfonts.com/) for icons

## License

MIT
