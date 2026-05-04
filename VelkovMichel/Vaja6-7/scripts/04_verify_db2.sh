#!/usr/bin/env bash
# Verify DB2 (installed via user-data)
# Usage:
#   chmod +x VelkovMichel/Vaja6-7/scripts/04_verify_db2.sh
#   VelkovMichel/Vaja6-7/scripts/04_verify_db2.sh <WEB_PUBLIC_IP> <DB2_PRIVATE_IP> <KEY_PATH>

set -euo pipefail

WEB_PUBLIC_IP="${1:-}"
DB2_PRIVATE_IP="${2:-}"
KEY_PATH="${3:-}"

if [[ -z "$WEB_PUBLIC_IP" || -z "$DB2_PRIVATE_IP" || -z "$KEY_PATH" ]]; then
  echo "ERROR: Missing args" >&2
  exit 1
fi

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@"$WEB_PUBLIC_IP" \
  "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/$(basename "$KEY_PATH") ubuntu@${DB2_PRIVATE_IP} 'apt list --installed 2>/dev/null | grep -i mariadb-server || true; systemctl status mariadb --no-pager'"
