#!/usr/bin/env bash
set -euo pipefail

CLUSTER_SIZE=3
JSON_FILE=".cluster_status_smart.json"

echo "🔍 Starting Smart Cluster Monitoring..."

while true; do
    echo "🕒 Checking VMs status at $(date)..."
    for i in $(seq 1 $CLUSTER_SIZE); do
        VM_NAME="RDP-VM${i}"
        if ! docker ps --format '{{.Names}}' | grep -q "^${VM_NAME}$"; then
            echo "⚠️ ${VM_NAME} is down. Recreating..."
            ./scripts/create_rdp_vm_smart.sh "${i}"
        else
            echo "✅ ${VM_NAME} is running."
            TS_IP=$(tailscale ip -4 | head -n1)
            if [ ! -f "${JSON_FILE}" ]; then echo "{}" > "${JSON_FILE}"; fi
            tmp=$(mktemp)
            jq --arg name "${VM_NAME}" --arg ip "${TS_IP}" '.[$name]=$ip' "${JSON_FILE}" > "${tmp}" && mv "${tmp}" "${JSON_FILE}" || true
        fi
    done
    echo "📊 Current Cluster Status:"
    [ -f "${JSON_FILE}" ] && jq . "${JSON_FILE}" || true
    sleep 300
done
