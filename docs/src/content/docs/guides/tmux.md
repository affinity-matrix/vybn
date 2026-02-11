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

All tmux shortcuts start with a **prefix key**: `Ctrl-b`.

The pattern is always two steps:

1. Press `Ctrl-b`, then release both keys
2. Press the action key

For example, to create a new window: press `Ctrl-b`, release, then press `c`.

## Essential shortcuts

| Action | Keys |
|--------|------|
| **Windows** | |
| Next window | `Ctrl-b` `n` |
| Previous window | `Ctrl-b` `p` |
| Go to window N | `Ctrl-b` `1`–`9` |
| List all windows | `Ctrl-b` `w` |
| Create new window | `Ctrl-b` `c` |
| Rename current window | `Ctrl-b` `,` |
| **Panes** | |
| Split vertically | `Ctrl-b` `%` |
| Split horizontally | `Ctrl-b` `"` |
| Switch between panes | `Ctrl-b` `arrow keys` |
| Close current pane | `Ctrl-d` or `exit` |
| **Session** | |
| Detach from session | `Ctrl-b` `d` |
| Scroll / copy mode | `Ctrl-b` `[` |

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
| Next / previous window | `Ctrl-b` `n` / `Ctrl-b` `p` |
| Jump to window by number | `Ctrl-b` `1`, `Ctrl-b` `2`, etc. |
| Pick from a list | `Ctrl-b` `w` (arrow keys + Enter) |

From your local machine, you can reconnect straight to a specific window:

```bash
vybn connect backend
```

See [Commands](/commands/) for full `vybn session` usage.

## vybn's tmux configuration

The VM ships with a `.tmux.conf` optimized for Claude Code sessions:

| Setting | Value |
|---------|-------|
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

- **Detach vs disconnect.** Pressing `Ctrl-b` `d` detaches you from tmux but leaves everything running — reconnect later with `vybn connect` and your session is intact. Closing the terminal or losing network connectivity has the same effect.
- **Sessions don't survive VM stop/start.** If you run `vybn stop` and then `vybn start`, the tmux session is gone. Use `vybn session` to recreate your windows. See [Troubleshooting](/troubleshooting/) for more details.
- **Exiting scroll mode.** After entering scroll mode with `Ctrl-b` `[`, press `q` to return to normal mode.
- **Scroll with the mouse.** Since mouse mode is on, scrolling your mouse wheel or trackpad enters copy mode automatically.

## Further reading

- [tmux wiki](https://github.com/tmux/tmux/wiki) — official documentation
- [tmux cheat sheet](https://tmuxcheatsheet.com/) — visual shortcut reference
