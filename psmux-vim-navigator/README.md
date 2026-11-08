# psmux-vim-navigator

Seamless, prefix-less `Ctrl+h/j/k/l` navigation between psmux panes and vim
splits. Port of [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator)
(tmux side) for [psmux](https://github.com/psmux/psmux).

When the active pane is running `vim`, `nvim`, `view`, or `fzf`, the key is
passed straight through to that program (so vim's own `<C-h/j/k/l>` split
navigation works normally). Otherwise psmux switches panes with
`select-pane -L/-D/-U/-R`, exactly like the upstream plugin.

## Installation (via PPM)

```tmux
set -g @plugin 'psmux-plugins/psmux-vim-navigator'
```

Then also install the vim side, which is what makes navigation work
seamlessly *from inside* vim splits, not just from psmux:

```vim
" vim-plug
Plug 'christoomey/vim-tmux-navigator'
```

The vim plugin shells out to `tmux` at the edge of a vim split. This works
unmodified on psmux because psmux ships `tmux.exe` as an alias for
`psmux.exe` and sets `$TMUX` inside every pane (verified: `$env:TMUX` is
populated and `tmux -V` resolves and runs correctly from inside a psmux
pane) -- no extra configuration needed on the vim side.

## Key Bindings

| Key | Action (non-vim pane) | Action (vim/nvim/fzf pane) |
|-----|------------------------|------------------------------|
| `Ctrl+h` | Select pane left | Sent to vim (`<C-h>`) |
| `Ctrl+j` | Select pane down | Sent to vim (`<C-j>`) |
| `Ctrl+k` | Select pane up | Sent to vim (`<C-k>`) |
| `Ctrl+l` | Select pane right | Sent to vim (`<C-l>`) |
| `Ctrl+\` | Select previous pane | Sent to vim (`<C-\>`) |
| `Prefix + Ctrl+l` | Clear screen (`send-keys C-l`) -- restored since `Ctrl+l` is claimed by the no-prefix binding above | |

Inside psmux copy-mode, `Ctrl+h/j/k/l/\` always navigate panes directly
(there's no vim process to defer to while you're already in psmux's own
copy mode).

## How vim-awareness works

As upstream vim-tmux-navigator does, each key is bound to
`if-shell -F '#{m/r:<vim-detect-pattern>,#{pane_current_command}}' 'send-keys <key>' 'select-pane -<dir>'`,
so the server checks the pane that receives the key on every keystroke, in
every session, with no lag after vim starts or exits. Verified with real
keypresses on psmux 3.4.0.

Earlier versions of this plugin rebound the keys from a background poller
(`scripts/poll-vim-state.ps1`), because psmux 3.3.6 dropped a key-bound
`if-shell` on a real keypress. The poller asked one session for its active
pane, so in every other session the keys stayed `select-pane` and never
reached vim. Loading this version stops a poller an earlier version left
running.

**Known limitation:** `#{pane_current_command}` names the deepest process
under the pane. A vim that runs child processes of its own (Neovim with
plugins starting `git` or a language server) can be reported as that child,
and the key then switches panes instead of reaching vim.

## Options

```tmux
set -g @vim_navigator_mapping_left   'C-h'
set -g @vim_navigator_mapping_down   'C-j'
set -g @vim_navigator_mapping_up     'C-k'
set -g @vim_navigator_mapping_right  'C-l'
set -g @vim_navigator_mapping_prev   'C-\'
set -g @vim_navigator_prefix_mapping_clear_screen 'C-l'
set -g @vim_navigator_pattern '(^|/)g?(view|l?n?vim?x?|fzf)(diff)?(\.exe)?$'
```

## License

MIT
