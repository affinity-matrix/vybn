#!/usr/bin/env bash
# IAP (Identity-Aware Proxy) network backend for vybn
# Implements the net_* and vybn_ssh* interface using gcloud IAP tunneling.

# --- Network Interface ---

net_setup() {
    # Create firewall rules (idempotent)
    if ! gcloud compute firewall-rules describe vybn-deny-all-ingress \
        --project="$VYBN_PROJECT" &>/dev/null; then
        info "Creating firewall rule: vybn-deny-all-ingress..."
        _retry gcloud compute firewall-rules create vybn-deny-all-ingress \
            --project="$VYBN_PROJECT" \
            --direction=INGRESS \
            --action=DENY \
            --rules=all \
            --source-ranges=0.0.0.0/0 \
            --target-tags=vybn-vm \
            --priority=1000 \
            --description="Deny all inbound traffic to vybn VMs" &>/dev/null
    else
        info "Firewall rule vybn-deny-all-ingress already exists."
    fi

    if ! gcloud compute firewall-rules describe vybn-allow-iap-ssh \
        --project="$VYBN_PROJECT" &>/dev/null; then
        info "Creating firewall rule: vybn-allow-iap-ssh..."
        _retry gcloud compute firewall-rules create vybn-allow-iap-ssh \
            --project="$VYBN_PROJECT" \
            --direction=INGRESS \
            --action=ALLOW \
            --rules=tcp:22 \
            --source-ranges=35.235.240.0/20 \
            --target-tags=vybn-vm \
            --priority=900 \
            --description="Allow SSH via IAP to vybn VMs" &>/dev/null
    else
        info "Firewall rule vybn-allow-iap-ssh already exists."
    fi
}

net_teardown() {
    for rule in vybn-deny-all-ingress vybn-allow-iap-ssh; do
        if gcloud compute firewall-rules describe "$rule" \
            --project="$VYBN_PROJECT" &>/dev/null; then
            info "Deleting firewall rule '${rule}'..."
            _retry gcloud compute firewall-rules delete "$rule" \
                --project="$VYBN_PROJECT" --quiet
        fi
    done
}

net_status() {
    echo "=== Network: IAP ==="
    info "SSH via Identity-Aware Proxy (gcloud IAP tunnel)"
}

net_ssh_raw() {
    local user="$1"
    shift
    gcloud compute ssh "${user}@${VYBN_VM_NAME}" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --tunnel-through-iap -- "$@"
}

vybn_ssh() {
    gcloud compute ssh "${VYBN_USER}@${VYBN_VM_NAME}" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --tunnel-through-iap -- -A "$@"
}

vybn_ssh_interactive() {
    # gcloud compute ssh allocates a PTY by default when stdin is a terminal
    gcloud compute ssh "${VYBN_USER}@${VYBN_VM_NAME}" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --tunnel-through-iap -- -A "$@"
}

net_tunnel() {
    local remote_port="$1"
    local local_port="$2"
    gcloud compute ssh "${VYBN_USER}@${VYBN_VM_NAME}" \
        --zone="$VYBN_ZONE" --project="$VYBN_PROJECT" \
        --tunnel-through-iap \
        -- -N -L "localhost:${local_port}:localhost:${remote_port}"
}
