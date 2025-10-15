#!/usr/bin/env bash
set -euo pipefail

VM_INDEX="${1:-1}"
VM_NAME="RDP-VM${VM_INDEX}"
JSON_FILE=".cluster_status_smart.json"

echo "🚀 Creating ${VM_NAME}..."

# إزالة أي حاوية قديمة بنفس الاسم
docker rm -f "${VM_NAME}" >/dev/null 2>&1 || true

# تشغيل الحاوية باستخدام صورة Tailscale الرسمية
docker run -d --name "${VM_NAME}" --hostname "${VM_NAME}" \
  --cap-add=NET_ADMIN --cap-add=SYS_MODULE \
  tailscale/tailscale:stable sleep infinity

echo "🛡️ Starting Tailscale inside ${VM_NAME}..."
docker exec -d "${VM_NAME}" tailscaled --state=/tmp/tailscaled.state

# Retry loop لتأكيد تشغيل tailscaled
for i in {1..10}; do
    if docker exec "${VM_NAME}" tailscale status >/dev/null 2>&1; then
        echo "✅ tailscaled is running."
        break
    fi
    echo "⏳ Waiting for tailscaled to start..."
    sleep 3
done

docker exec "${VM_NAME}" tailscale up --authkey="${TAILSCALE_AUTH_KEY}" --hostname="${VM_NAME}" || true

TS_IP=$(docker exec "${VM_NAME}" tailscale ip -4 | head -n1)
echo "✅ ${VM_NAME} created with Tailscale IP: ${TS_IP}"

# تحديث JSON cluster status
if [ ! -f "${JSON_FILE}" ]; then
  echo "{}" > "${JSON_FILE}"
fi
tmp=$(mktemp)
jq --arg name "${VM_NAME}" --arg ip "${TS_IP}" '.[$name]=$ip' "${JSON_FILE}" > "${tmp}" && mv "${tmp}" "${JSON_FILE}" || echo "{}" > "${JSON_FILE}"

# إرسال إشعار Gmail (اختياري)
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
