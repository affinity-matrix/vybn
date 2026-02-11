---
title: Working with tmux
description: How to navigate tmux sessions, windows, and panes on your vybn VM.
---

tmux is a terminal multiplexer — it lets you run multiple terminal sessions inside a single connection, and keeps them alive even when you disconnect. vybn uses tmux to make Claude Code sessions persistent: you can close your laptop, reconnect from another device, and pick up exactly where you left off.

## The basics

```bash
# First time — creates a session and attaches
vybn connect

# Close your laptop, go get coffee, switch to your phone...

# Reconnect — you're right where you left off
vybn connect
```

That's all there is to it. `vybn connect` attaches to the existing session, or creates one if none exists. Everything you were doing — running processes, Claude Code conversations, terminal output — is still there.

### Named windows

You can jump straight to a specific project window by name:

```bash
vybn connect backend
```

If the window exists, it's selected. If it doesn't exist, it's created. You never need to worry about whether it's there yet.

## Key concepts

When you `vybn connect`, you're attached to a **tmux session** named `claude` (configurable via `VYBN_TMUX_SESSION`). Inside that session:

- **Windows** are like tabs. Each window typically runs a Claude Code instance for a different project. The status bar at the bottom shows your windows.
- **Panes** are splits within a window. You can divide a window horizontally or vertically to see multiple terminals side by side.

## The prefix key

All tmux shortcuts start with a **prefix key**: `Ctrl-a`.

vybn uses `Ctrl-a` (GNU Screen's classic keybinding) instead of tmux's default `Ctrl-b` because it's easier to type on mobile keyboards — `a` is on the home row and much more accessible with modifier keys on touch screens. It's also familiar to longtime Screen users.

The pattern is always two steps:

1. Press `Ctrl-a`, then release both keys
2. Press the action key

For example, to create a new window: press `Ctrl-a`, release, then press `c`.

:::note[Prefer Ctrl-b?]
If you're used to tmux's default prefix, you can change it back by editing `~/.tmux.conf` on the VM and running `tmux source-file ~/.tmux.conf`.
:::

## Essential shortcuts

| Action | Keys |
|--------|------|
| **Windows** | |
| Next window | `Ctrl-a` `n` |
| Previous window | `Ctrl-a` `p` |
| Go to window N | `Ctrl-a` `1`–`9` |
| List all windows | `Ctrl-a` `w` |
| Create new window | `Ctrl-a` `c` |
| Rename current window | `Ctrl-a` `,` |
| **Panes** | |
| Split vertically | `Ctrl-a` `%` |
| Split horizontally | `Ctrl-a` `"` |
| Switch between panes | `Ctrl-a` `arrow keys` |
| Close current pane | `Ctrl-d` or `exit` |
| **Session** | |
| Detach from session | `Ctrl-a` `d` |
| Scroll / copy mode | `Ctrl-a` `[` |

:::tip
Mouse mode is enabled by default on vybn VMs. You can click on windows in the status bar, click to switch panes, and scroll with your mouse wheel or trackpad.
:::

## Working with multiple projects

Use `vybn session` to create named windows, each running Claude Code in its own directory:

```bash
# From your local machine
vybn session myapp ~/projects/myapp
vybn session backend ~/projects/backend
```

Each command creates a named window running Claude Code in the given directory.

### Switching between projects

From inside tmux:

| Method | Keys |
|--------|------|
| Next / previous window | `Ctrl-a` `n` / `Ctrl-a` `p` |
| Jump to window by number | `Ctrl-a` `1`, `Ctrl-a` `2`, etc. |
| Pick from a list | `Ctrl-a` `w` (arrow keys + Enter) |

From your local machine, you can reconnect straight to a specific window:

```bash
vybn connect backend
```

See [Commands](/commands/) for full `vybn session` usage.

## vybn's tmux configuration

The VM ships with a `.tmux.conf` optimized for Claude Code sessions:

| Setting | Value |
|---------|-------|
| Prefix key | `Ctrl-a` |
| Mouse mode | On |
| Window numbering | Starts at 1 |
| Scroll history | 50,000 lines |
| Escape time | 10ms (no delay for Vim/Escape key) |
| Terminal colors | 256-color with true color support |
| Window renumbering | Automatic (no gaps after closing) |

The status bar shows the session name on the left (in green), window list in the center, and the time on the right. The current window is highlighted in orange.

You can customize these settings by editing `~/.tmux.conf` on the VM. Changes take effect after reloading:

```bash
tmux source-file ~/.tmux.conf
```

## Tips

- **Detach vs disconnect.** Pressing `Ctrl-a` `d` detaches you from tmux but leaves everything running — reconnect later with `vybn connect` and your session is intact. Closing the terminal or losing network connectivity has the same effect.
- **Sessions don't survive VM stop/start.** If you run `vybn stop` and then `vybn start`, the tmux session is gone. Use `vybn session` to recreate your windows. See [Troubleshooting](/troubleshooting/) for more details.
- **Exiting scroll mode.** After entering scroll mode with `Ctrl-a` `[`, press `q` to return to normal mode.
- **Scroll with the mouse.** Since mouse mode is on, scrolling your mouse wheel or trackpad enters copy mode automatically.

## Further reading

- [tmux wiki](https://github.com/tmux/tmux/wiki) — official documentation
- [tmux cheat sheet](https://tmuxcheatsheet.com/) — visual shortcut reference
