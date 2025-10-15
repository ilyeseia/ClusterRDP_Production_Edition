#!/usr/bin/env bash
set -euo pipefail

VM_INDEX="$1"
if [ -z "$VM_INDEX" ]; then
  echo "Usage: $0 <VM_INDEX>"
  exit 1
fi

VM_NAME="RDP-VM${VM_INDEX}"
JSON_FILE=".cluster_status_smart.json"

echo "ðŸš€ Creating ${VM_NAME}..."

# Remove any previous container with same name
docker rm -f "${VM_NAME}" >/dev/null 2>&1 || true

# Launch Ubuntu container to simulate VM with GUI (xRDP) and Tailscale
docker run -d --name "${VM_NAME}" --hostname "${VM_NAME}" --privileged --network host ubuntu:22.04 sleep infinity

echo "ðŸ”§ Installing desktop components and tailscale inside ${VM_NAME} (this may take a minute)..."
docker exec -i "${VM_NAME}" bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xfce4 xfce4-goodies xrdp dbus-x11 curl ca-certificates jq sudo python3 python3-pip && apt-get clean"

# Install tailscale binary inside container (stable install script)
docker exec -i "${VM_NAME}" bash -c "curl -fsSL https://pkgs.tailscale.com/stable/install.sh | sh || true"

# Start tailscaled inside container and bring up with authkey (non-fatal)
docker exec -d "${VM_NAME}" bash -c "nohup tailscaled --state=/var/lib/tailscale/tailscaled.state >/tmp/tailscaled.log 2>&1 &"
sleep 2
docker exec -i "${VM_NAME}" bash -c "tailscale up --authkey='${TAILSCALE_AUTH_KEY}' --hostname='${VM_NAME}' --accept-dns=false || true"

# Ensure xrdp running
docker exec -d "${VM_NAME}" bash -c "service dbus start || true; service xrdp start || true"

# Extract tailscale IP (best effort)
TS_IP=$(docker exec "${VM_NAME}" bash -c "tailscale ip -4 2>/dev/null | grep '^100\.' | head -n1 || true" || true)
TS_IP=${TS_IP:-""}
echo "âœ… ${VM_NAME} created with Tailscale IP: ${TS_IP}"

# Update JSON cluster status
if [ ! -f "${JSON_FILE}" ]; then
  echo "{}" > "${JSON_FILE}"
fi
# Use jq to update or insert
tmp=$(mktemp)
jq --arg name "${VM_NAME}" --arg ip "${TS_IP}" '.[$name]=$ip' "${JSON_FILE}" > "${tmp}" && mv "${tmp}" "${JSON_FILE}" || echo "{}" > "${JSON_FILE}"

# Gmail notification (best-effort)
if [ -n "${GMAIL_USER:-}" ] && [ -n "${GMAIL_PASS:-}" ]; then
  python3 - <<PYCODE || true
import smtplib, ssl, os
from email.mime.text import MIMEText
user=os.getenv("GMAIL_USER")
pwd=os.getenv("GMAIL_PASS")
vmname="${VM_NAME}"
ip="${TS_IP}"
body=f"ClusterRDP Notification:\n\nVM: {vmname}\nTailscale IP: {ip}\nTime: {__import__('time').ctime()}"
msg=MIMEText(body)
msg["Subject"]="ClusterRDP - VM Created: {vmname}"
msg["From"]=user
msg["To"]=user
context=ssl.create_default_context()
try:
    with smtplib.SMTP("smtp.gmail.com",587) as s:
        s.starttls(context=context)
        s.login(user,pwd)
        s.send_message(msg)
except Exception as e:
    print('Email failed:', e)
PYCODE
fi

echo "Created ${VM_NAME} and notified via Gmail (if configured)."
