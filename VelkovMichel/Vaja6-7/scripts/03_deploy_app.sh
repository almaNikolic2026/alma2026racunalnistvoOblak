#!/usr/bin/env bash
# Deploy app files to WEB EC2 and set DB private IP in config.php.
# Usage:
#   chmod +x VelkovMichel/Vaja6-7/scripts/03_deploy_app.sh
#   VelkovMichel/Vaja6-7/scripts/03_deploy_app.sh <WEB_PUBLIC_IP> <DB1_PRIVATE_IP> <KEY_PATH> [SSH_USER]
# Example:
#   VelkovMichel/Vaja6-7/scripts/03_deploy_app.sh 18.199.10.10 192.168.0.140 v7-michel-key.pem ubuntu

set -euo pipefail

WEB_PUBLIC_IP="${1:-}"
DB1_PRIVATE_IP="${2:-}"
KEY_PATH="${3:-}"
SSH_USER="${4:-ubuntu}"

if [[ -z "$WEB_PUBLIC_IP" || -z "$DB1_PRIVATE_IP" || -z "$KEY_PATH" ]]; then
  echo "ERROR: Missing args" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../app" && pwd)"

cp -r "$APP_DIR" "$TMP_DIR/app"
sed -i "s/DB1_PRIVATE_IP/${DB1_PRIVATE_IP}/g" "$TMP_DIR/app/config.php"

scp -i "$KEY_PATH" -o StrictHostKeyChecking=no -r "$TMP_DIR/app" "${SSH_USER}@${WEB_PUBLIC_IP}:/home/${SSH_USER}/"
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no "${SSH_USER}@${WEB_PUBLIC_IP}" \
  "sudo cp -r /home/${SSH_USER}/app/* /var/www/html/ && sudo chown -R www-data:www-data /var/www/html && sudo systemctl restart apache2 && sudo php -l /var/www/html/vstavi.php && sudo php -l /var/www/html/izpis.php"

echo "Deploy complete"
echo "Open: http://${WEB_PUBLIC_IP}/index.html"
echo "Open: http://${WEB_PUBLIC_IP}/izpis.php"
echo "If app still fails, run:"
echo "ssh -i ${KEY_PATH} ${SSH_USER}@${WEB_PUBLIC_IP} 'sudo tail -n 80 /var/log/apache2/error.log'"
