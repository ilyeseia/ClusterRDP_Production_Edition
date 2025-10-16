#!/usr/bin/env bash
set -euo pipefail

CLUSTER_SIZE=3
JSON_FILE=".cluster_status_smart.json"
LOG_FILE="monitor.log"
MAX_RUNTIME_MINUTES=30  # ⏱️ مدة المراقبة 30 دقيقة فقط
CHECK_INTERVAL=300      # كل 5 دقائق

echo "🔍 Starting Smart Cluster Monitoring..." | tee -a "$LOG_FILE"
echo "⏱️ Monitoring limited to $MAX_RUNTIME_MINUTES minutes..." | tee -a "$LOG_FILE"

start_time=$(date +%s)
end_time=$((start_time + MAX_RUNTIME_MINUTES * 60))

while [ "$(date +%s)" -lt "$end_time" ]; do
    echo "🕒 Checking VMs status at $(date)..." | tee -a "$LOG_FILE"

    for i in $(seq 1 $CLUSTER_SIZE); do
        VM_NAME="RDP-VM${i}"
        HOSTNAME_TAG="rdp-vm-$RANDOM"
        echo "🔹 Inspecting $VM_NAME..." | tee -a "$LOG_FILE"

        if ! docker ps --format '{{.Names}}' | grep -q "^${VM_NAME}$"; then
            echo "⚠️ ${VM_NAME} is down. Attempting recreation..." | tee -a "$LOG_FILE"

            retry=0
            until ./scripts/create_rdp_vm_smart.sh "${i}" "$HOSTNAME_TAG"; do
                retry=$((retry + 1))
                if [ $retry -ge 3 ]; then
                    echo "❌ Failed to recreate ${VM_NAME} after 3 attempts." | tee -a "$LOG_FILE"
                    break
                fi
                echo "🔁 Retry #${retry} in 10 seconds..." | tee -a "$LOG_FILE"
                sleep 10
            done
        else
            echo "✅ ${VM_NAME} is running." | tee -a "$LOG_FILE"
            TS_IP=$(tailscale ip -4 | head -n1 || echo "unknown")
            if [ ! -f "${JSON_FILE}" ]; then echo "{}" > "${JSON_FILE}"; fi
            tmp=$(mktemp)
            jq --arg name "${VM_NAME}" --arg ip "${TS_IP}" '.[$name]=$ip' "${JSON_FILE}" > "${tmp}" && mv "${tmp}" "${JSON_FILE}" || true
        fi
    done

    echo "📊 Current Cluster Status:" | tee -a "$LOG_FILE"
    [ -f "${JSON_FILE}" ] && jq . "${JSON_FILE}" | tee -a "$LOG_FILE" || true

    echo "💤 Sleeping for $(($CHECK_INTERVAL / 60)) minutes before next check..." | tee -a "$LOG_FILE"
    sleep "$CHECK_INTERVAL"
done

echo "✅ Monitoring finished gracefully after $MAX_RUNTIME_MINUTES minutes." | tee -a "$LOG_FILE"
