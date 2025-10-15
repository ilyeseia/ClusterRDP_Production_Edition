#!/usr/bin/env bash
set -euo pipefail

CLUSTER_SIZE=3
JSON_FILE=".cluster_status_smart.json"

echo "ðŸ” Starting Smart Cluster Monitoring (production timings)..."

while true; do
  echo "ðŸ’¡ Checking VMs status at $(date)..."
  for i in $(seq 1 $CLUSTER_SIZE); do
    VM_NAME="RDP-VM${i}"
    # check if container exists and running
    if ! docker ps --format '{{.Names}}' | grep -q "^${VM_NAME}$"; then
      echo "âš  ${VM_NAME} is down or missing. Recreating..."
      ./scripts/create_rdp_vm_smart.sh ${i}
    else
      echo "âœ… ${VM_NAME} is running."
      # refresh Tailscale IP (best-effort)
      TS_IP=$(docker exec ${VM_NAME} bash -c "tailscale ip -4 2>/dev/null | grep '^100.' | head -n1 || true" || true)
      if [ ! -f "${JSON_FILE}" ]; then
        echo "{}" > "${JSON_FILE}"
      fi
      tmp=$(mktemp)
      jq --arg name "${VM_NAME}" --arg ip "${TS_IP}" '.[$name]=$ip' "${JSON_FILE}" > "${tmp}" && mv "${tmp}" "${JSON_FILE}" || true
    fi
  done

  # print status
  echo "ðŸ“‹ Current Cluster Status:"
  if [ -f "${JSON_FILE}" ]; then
    jq . "${JSON_FILE}" || true
  fi

  # sleep for 5 minutes between checks
  sleep 300
done
