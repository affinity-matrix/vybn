---
title: Git & GitHub
description: Using Git and GitHub from the VM with SSH agent forwarding.
---

vybn forwards your local SSH agent to the VM automatically, so you can push to GitHub (or any Git remote) using the SSH keys on your local machine — no credentials need to be stored on the VM.

## Setup

### 1. Add an SSH key to GitHub

If you haven't already:
- [Generate a new SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent)
- [Add the public key to your GitHub account](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)

### 2. Load your key locally

Make sure your SSH key is loaded in your local agent before connecting:

```bash
# Check if your key is loaded
ssh-add -l

# If not, add it
ssh-add ~/.ssh/id_ed25519
```

### 3. Connect and use Git

```bash
vybn connect
```

On the VM, Git operations over SSH work normally:

```bash
git clone git@github.com:youruser/yourrepo.git
git push origin main
```

## Notes

- Agent forwarding only lasts for the duration of your SSH session. If you disconnect and reconnect, forwarding resumes automatically as long as your local agent still has the key loaded.
- Use **SSH URLs** (`git@github.com:...`) for remotes, not HTTPS URLs.
- If `ssh-add -l` shows "The agent has no identities" on your local machine, your key isn't loaded and forwarding won't work.
