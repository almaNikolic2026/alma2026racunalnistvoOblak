#!/usr/bin/env bash
# Configure DB1 automatically through WEB jump host.
# Usage:
#   chmod +x VelkovMichel/Vaja6-7/scripts/02_configure_db1.sh
#   VelkovMichel/Vaja6-7/scripts/02_configure_db1.sh <WEB_PUBLIC_IP> <DB1_PRIVATE_IP> <KEY_PATH> [SSH_USER]
# Example:
#   VelkovMichel/Vaja6-7/scripts/02_configure_db1.sh 18.199.10.10 192.168.0.140 v7-michel-key.pem ubuntu

set -euo pipefail

WEB_PUBLIC_IP="${1:-}"
DB1_PRIVATE_IP="${2:-}"
KEY_PATH="${3:-}"
SSH_USER="${4:-ubuntu}"

if [[ -z "$WEB_PUBLIC_IP" || -z "$DB1_PRIVATE_IP" || -z "$KEY_PATH" ]]; then
  echo "ERROR: Missing args" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SCRIPT="$SCRIPT_DIR/helper_db1_commands.sh"

if [[ ! -f "$HELPER_SCRIPT" ]]; then
  echo "ERROR: helper script not found: $HELPER_SCRIPT" >&2
  exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
  echo "ERROR: key not found: $KEY_PATH" >&2
  exit 1
fi

KEY_BASENAME="$(basename "$KEY_PATH")"

# Copy helper and key to WEB host
scp -i "$KEY_PATH" -o StrictHostKeyChecking=no "$HELPER_SCRIPT" "${SSH_USER}@${WEB_PUBLIC_IP}:/home/${SSH_USER}/"
scp -i "$KEY_PATH" -o StrictHostKeyChecking=no "$KEY_PATH" "${SSH_USER}@${WEB_PUBLIC_IP}:/home/${SSH_USER}/${KEY_BASENAME}"

# From WEB host copy helper to DB1 and execute it
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no "${SSH_USER}@${WEB_PUBLIC_IP}" <<EOF
set -euo pipefail
chmod 400 /home/${SSH_USER}/${KEY_BASENAME}
scp -i /home/${SSH_USER}/${KEY_BASENAME} -o StrictHostKeyChecking=no /home/${SSH_USER}/helper_db1_commands.sh ubuntu@${DB1_PRIVATE_IP}:/home/ubuntu/helper_db1_commands.sh
ssh -i /home/${SSH_USER}/${KEY_BASENAME} -o StrictHostKeyChecking=no ubuntu@${DB1_PRIVATE_IP} 'chmod +x /home/ubuntu/helper_db1_commands.sh && bash /home/ubuntu/helper_db1_commands.sh'
EOF

echo "DB1 configured successfully"
