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

## How vim-awareness works on psmux 3.3.6 (read this if something looks off)

Upstream vim-tmux-navigator binds each key directly to
`if-shell -F '<vim-detect-pattern>' 'send-keys <key>' 'select-pane -<dir>'`,
so tmux re-checks the condition on every keystroke. That exact mechanism
was prototyped for this plugin and confirmed to *register* correctly on
psmux 3.3.6, and the detection condition itself evaluates correctly on
demand (`#{m/r:<pattern>,#{pane_current_command}}` reliably returns `nvim`
for nvim panes, `vim` for vim panes, and the shell name for idle panes,
thanks to the immediate-child `pane_current_command` fix in
[psmux/psmux#299](https://github.com/psmux/psmux/issues/299), commit
`b003802`) -- but the bound `if-shell`/`run-shell` command never actually
fires its chosen branch when triggered by a *real keypress*. This was
verified directly with `WriteConsoleInput` keystroke injection against an
attached psmux client (not `send-keys`, which bypasses the key-dispatch
path entirely and would have masked the bug).

Root cause, found in the psmux source
(`src/commands.rs`, the `"if-shell" | "if"` and `"run-shell" | "run"` match
arms inside `execute_command_string`): whenever the invoking client has
`app.control_port` set -- true for essentially every attached session --
the command is forwarded to the server's control port via
`send_control_to_port(...)` and the result is discarded (`let _ = ...`).
The fully correct local-evaluation branch (parse the condition, run the
format/shell test, dispatch the chosen command) exists right below it, but
is dead code in practice because `control_port` is always set for a normal
attached client. `confirm-before`, by contrast, is handled entirely
locally (it just sets `app.mode` directly) and dispatches correctly on
every real keypress, which is what confirmed this is specific to the
if-shell/run-shell forwarding path rather than root-table dispatch or
compound commands in general.

**Until that's fixed upstream**, this plugin uses a different, verified
mechanism to get the same end-user behavior: `scripts/poll-vim-state.ps1`
runs as a lightweight background process that watches
`#{pane_current_command}` for the active pane and re-binds the direction
keys between two plain, non-conditional commands (`select-pane -<dir>` /
`send-keys <key>`), which *do* dispatch correctly on every real keypress.
This was proven end-to-end with real `WriteConsoleInput` injection: typing
`Ctrl+h` while nvim is running and in insert mode with placeholder text
correctly triggers nvim's own backspace (the keystroke reaches vim), and
typing `Ctrl+h` from a plain shell pane correctly switches panes.

The trade-off is a small, bounded lag (one poll interval, default 250ms)
right after vim/nvim starts or exits in the active pane, during which a
navigation key might still do the "old" behavior. Once psmux's `if-shell`
key-binding dispatch is fixed, this plugin can go back to the simpler,
zero-lag upstream mechanism.

**Known limitation:** because the poller re-binds a single, server-wide
root-table key rather than evaluating per-keystroke in each client's own
context, this only tracks one active pane's vim state at a time. If you
have multiple clients attached simultaneously to different panes with
different vim states, they will all currently share whichever pane's state
the poller last observed. This is a corollary of the same core limitation,
not a separate bug.

## Options

```tmux
set -g @vim_navigator_mapping_left   'C-h'
set -g @vim_navigator_mapping_down   'C-j'
set -g @vim_navigator_mapping_up     'C-k'
set -g @vim_navigator_mapping_right  'C-l'
set -g @vim_navigator_mapping_prev   'C-\'
set -g @vim_navigator_prefix_mapping_clear_screen 'C-l'
set -g @vim_navigator_pattern '(^|/)g?(view|l?n?vim?x?|fzf)(diff)?(\.exe)?$'
set -g @vim_navigator_poll_interval_ms '250'
```

## License

MIT
