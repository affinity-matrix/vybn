#!/usr/bin/env bash
# GCP provider backend for vybn
# Implements the provider_* interface using gcloud CLI.

# GCP-specific defaults
VYBN_GCP_SCOPES="${VYBN_GCP_SCOPES:-compute-ro,logging-write,storage-ro}"

# --- Provider Interface ---

provider_require_cli() {
    if ! command -v gcloud &>/dev/null; then
        error "gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    if ! gcloud auth print-access-token &>/dev/null; then
        error "gcloud credentials are expired or missing."
        error "Run: gcloud auth login"
        exit 1
    fi
    if [[ -z "$VYBN_PROJECT" ]]; then
        error "No GCP project set. Run: gcloud config set project <project-id>"
        exit 1
    fi
}

provider_detect_project() {
    gcloud config get-value project 2>/dev/null || true
}

provider_vm_exists() {
    gcloud compute instances describe "$VYBN_VM_NAME" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" &>/dev/null
}

provider_vm_status() {
    gcloud compute instances describe "$VYBN_VM_NAME" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --format='get(status)' 2>/dev/null
}

provider_vm_info() {
    gcloud compute instances describe "$VYBN_VM_NAME" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --format='yaml(status,machineType,networkInterfaces[0].accessConfigs[0].natIP,creationTimestamp)' 2>/dev/null
}

provider_vm_create() {
    local setup_script="$1"

    local create_args=(
        "$VYBN_VM_NAME"
        --project="$VYBN_PROJECT"
        --zone="$VYBN_ZONE"
        --machine-type="$VYBN_MACHINE_TYPE"
        --image-family=ubuntu-2404-lts-amd64
        --image-project=ubuntu-os-cloud
        --boot-disk-size="${VYBN_DISK_SIZE}GB"
        --boot-disk-type=pd-ssd
        --tags=vybn-vm
        --scopes="$VYBN_GCP_SCOPES"
        --metadata-from-file=startup-script="$setup_script"
    )

    # Disable external IP by default (IAP and Tailscale don't need one)
    if [[ "${VYBN_EXTERNAL_IP}" != "true" ]]; then
        create_args+=(--no-address)
    fi

    # Guest attributes for out-of-band status reporting during setup
    create_args+=(--metadata="enable-guest-attributes=TRUE")

    _retry gcloud compute instances create "${create_args[@]}"
}

provider_vm_start() {
    _retry gcloud compute instances start "$VYBN_VM_NAME" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT"
}

provider_vm_stop() {
    _retry gcloud compute instances stop "$VYBN_VM_NAME" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT"
}

provider_vm_delete() {
    _retry gcloud compute instances delete "$VYBN_VM_NAME" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --delete-disks=boot --quiet
}
