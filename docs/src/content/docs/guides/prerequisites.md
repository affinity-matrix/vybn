---
title: Prerequisites
description: Set up your cloud provider and Tailscale before deploying your first vybn VM.
---

This guide walks through everything you need before running `vybn deploy`. Choose your provider — GCP (managed VM) or SSH (bring your own server) — and follow the relevant sections.

## GCP Provider

### 1. Google Cloud account & project

You need a GCP account with a project that has billing enabled.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and sign in (or create an account)
2. Create a new project — or use an existing one
3. [Enable billing](https://console.cloud.google.com/billing) on the project

:::note
vybn creates a single `e2-standard-4` VM by default. See [GCP pricing](https://cloud.google.com/compute/vm-instance-pricing) for current costs. You can change the machine type with `VYBN_MACHINE_TYPE` in `~/.vybnrc`.
:::

### 2. Install the gcloud CLI

Install the Google Cloud SDK for your platform:

**macOS (Homebrew):**

```bash
brew install google-cloud-sdk
```

**macOS / Linux (manual):**

```bash
curl https://sdk.cloud.google.com | bash
```

**Other platforms:** see the [official install docs](https://cloud.google.com/sdk/docs/install).

After installing, initialize and authenticate:

```bash
gcloud init
gcloud auth login
```

`gcloud init` will prompt you to select a project and default region. Pick the project you created in step 1.

:::tip
To change your project later: `gcloud config set project PROJECT_ID`
:::

### 3. Enable the Compute Engine API

vybn creates VMs through the Compute Engine API, which must be enabled on your project:

```bash
gcloud services enable compute.googleapis.com
```

## SSH Provider

The SSH provider deploys to an existing server you manage. No GCP account or `gcloud` CLI required.

### 1. Server requirements

- **OS:** Ubuntu 22.04+, Ubuntu 24.04, or Debian 12+
- **Access:** root or a user with passwordless sudo
- **Network:** outbound internet access (to install packages and connect to Tailscale)
- **SSH:** the server must be reachable from your local machine via SSH

### 2. SSH client

You need an SSH client on your local machine. macOS and Linux include one by default. Verify with:

```bash
ssh -V
```

### 3. SSH credentials

Ensure you can connect to your server:

```bash
ssh user@your-server.example.com
```

If you use a specific key file, note its path — you'll provide it during `vybn init` (or set `VYBN_SSH_KEY` in `~/.vybnrc`).

## Tailscale account & auth key

Tailscale is the default network backend for both providers. It creates a WireGuard mesh so your VM is reachable from any device on your tailnet.

:::note[Using IAP instead? (GCP only)]
If you're using the GCP provider and prefer to tunnel SSH through Google's infrastructure, you can skip this section. See the [IAP Setup guide](/guides/iap/).
:::

1. Create a free account at [tailscale.com](https://tailscale.com/)
2. Install Tailscale on your local machine: [tailscale.com/download](https://tailscale.com/download)
3. Log in and verify it's running:

```bash
tailscale status
```

4. Generate an auth key in the [admin console](https://login.tailscale.com/admin/settings/keys)

   - Use a **reusable** key if you plan to redeploy VMs frequently
   - Set an appropriate expiration (90 days is the maximum)

5. Save the key in your vybn config:

```bash
cat >> ~/.vybnrc << 'EOF'
VYBN_TAILSCALE_AUTHKEY="tskey-auth-..."
EOF
```

For more Tailscale options (custom hostname, ACL tags), see the [Tailscale Setup guide](/guides/tailscale/).

## Next steps

You're ready to install vybn and deploy your first VM. Head to [Getting Started](/getting-started/).
