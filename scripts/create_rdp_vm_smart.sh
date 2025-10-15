#!/usr/bin/env bash
set -euo pipefail

VM_INDEX="${1:-1}"
VM_NAME="RDP-VM${VM_INDEX}"
JSON_FILE=".cluster_status_smart.json"

echo "🚀 Creating ${VM_NAME}..."

docker rm -f "${VM_NAME}" >/dev/null 2>&1 || true

# إنشاء container Ubuntu مع XFCE و xRDP
docker run -d --name "${VM_NAME}" --hostname "${VM_NAME}" --network host \
  ubuntu:22.04 sleep infinity

echo "🛠 Installing desktop and RDP inside ${VM_NAME}..."
docker exec -i "${VM_NAME}" bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y xfce4 xfce4-goodies xrdp sudo python3 python3-pip curl jq && apt-get clean"

# تشغيل xrdp
docker exec -d "${VM_NAME}" bash -c "service dbus start || true; service xrdp start || true"

# استخراج IP host runner (Tailscale IP)
TS_IP=$(tailscale ip -4 | head -n1)

echo "✅ ${VM_NAME} created. Runner Tailscale IP: ${TS_IP}"

# تحديث JSON cluster status
if [ ! -f "${JSON_FILE}" ]; then echo "{}" > "${JSON_FILE}"; fi
tmp=$(mktemp)
jq --arg name "${VM_NAME}" --arg ip "${TS_IP}" '.[$name]=$ip' "${JSON_FILE}" > "${tmp}" && mv "${tmp}" "${JSON_FILE}" || echo "{}" > "${JSON_FILE}"

# إرسال إشعار Gmail
if [ -n "${GMAIL_USER:-}" ] && [ -n "${GMAIL_PASS:-}" ]; then
python3 - <<PYCODE || true
import smtplib, ssl, os
from email.mime.text import MIMEText
user=os.getenv("GMAIL_USER")
pwd=os.getenv("GMAIL_PASS")
vmname="${VM_NAME}"
ip="${TS_IP}"
body=f"ClusterRDP Notification:\\n\\nVM: {vmname}\\nTailscale IP: {ip}\\nTime: {__import__('time').ctime()}"
msg=MIMEText(body)
msg["Subject"]=f"ClusterRDP - VM Created: {vmname}"
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
