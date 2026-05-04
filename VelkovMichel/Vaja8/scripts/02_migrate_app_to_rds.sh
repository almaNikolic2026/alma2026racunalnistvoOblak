#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f "./rds_outputs.env" ]]; then
  echo "ERROR: manjka rds_outputs.env (najprej zazeni 01_setup_rds.sh)."
  exit 1
fi

# shellcheck disable=SC1091
source ./rds_outputs.env

KEY_PATH="${KEY_PATH:-}"
WEB_USER="${WEB_USER:-ubuntu}"
APP_DB_USER="${APP_DB_USER:-nakup_app}"
APP_DB_PASS="${APP_DB_PASS:-ChangeThisStrongPass123!}"
APP_PATH="${APP_PATH:-/var/www/html}"

if [[ -z "${KEY_PATH}" || ! -f "${KEY_PATH}" ]]; then
  DETECTED_KEY_PATH="$(find "${HOME}" -maxdepth 4 -type f -name "*.pem" | head -n 1 || true)"
  if [[ -n "${DETECTED_KEY_PATH}" ]]; then
    KEY_PATH="${DETECTED_KEY_PATH}"
  fi
fi

if [[ -z "${KEY_PATH}" || ! -f "${KEY_PATH}" ]]; then
  echo "ERROR: .pem kljuc ni najden."
  echo "Nalozi kljuc v CloudShell (Actions -> Upload file) in nastavi KEY_PATH."
  echo "Primer: export KEY_PATH=\"$HOME/v7-michel-key.pem\""
  echo "Pomoc: find \"$HOME\" -maxdepth 4 -type f -name \"*.pem\""
  exit 1
fi

chmod 400 "${KEY_PATH}" >/dev/null 2>&1 || true
echo "Uporabljam KEY_PATH=${KEY_PATH}"

if [[ -z "${DB_ADMIN_PASS:-}" || -z "${RDS_ENDPOINT:-}" ]]; then
  echo "ERROR: manjkajo vrednosti v rds_outputs.env"
  exit 1
fi

WEB_STATE="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --instance-ids "${WEB_INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text)"

if [[ "${WEB_STATE}" == "stopping" ]]; then
  echo "WEB instanca je stopping, cakam na stopped ..."
  aws ec2 wait instance-stopped --region "${AWS_REGION}" --instance-ids "${WEB_INSTANCE_ID}"
  WEB_STATE="stopped"
fi

if [[ "${WEB_STATE}" == "stopped" ]]; then
  echo "WEB instanca je stopped, izvajam start ..."
  aws ec2 start-instances --region "${AWS_REGION}" --instance-ids "${WEB_INSTANCE_ID}" >/dev/null
  aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${WEB_INSTANCE_ID}"
fi

WEB_PUBLIC_IP="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --instance-ids "${WEB_INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)"

if [[ -z "${WEB_PUBLIC_IP}" || "${WEB_PUBLIC_IP}" == "None" ]]; then
  echo "ERROR: web instanca nima javnega IP ali ni dosegljiva."
  exit 1
fi

echo "[1/6] Test SSH na web instanco"
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no "${WEB_USER}@${WEB_PUBLIC_IP}" "echo SSH_OK"

echo "[2/6] Namestim mariadb-client na WEB EC2"
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no "${WEB_USER}@${WEB_PUBLIC_IP}" \
  "sudo DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-client >/dev/null"

echo "[3/6] Ustvarim DB strukturo in uporabnika na RDS"
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no "${WEB_USER}@${WEB_PUBLIC_IP}" \
  "export MYSQL_PWD='${DB_ADMIN_PASS}'; mariadb -h '${RDS_ENDPOINT}' -u '${DB_ADMIN_USER}' <<'SQL'
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
USE ${DB_NAME};
CREATE TABLE IF NOT EXISTS nakup (
  id INT AUTO_INCREMENT PRIMARY KEY,
  element VARCHAR(255) NOT NULL,
  kolicina INT NOT NULL
);
CREATE USER IF NOT EXISTS '${APP_DB_USER}'@'%' IDENTIFIED BY '${APP_DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${APP_DB_USER}'@'%';
FLUSH PRIVILEGES;
INSERT INTO nakup (element, kolicina) VALUES ('kruh',1),('mleko',2),('pivo',6);
SELECT * FROM nakup;
SQL"

echo "[4/6] Posodobim app config.php"
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no "${WEB_USER}@${WEB_PUBLIC_IP}" \
  "cat > /tmp/config.php <<'PHP'
<?php
\$host = '${RDS_ENDPOINT}';
\$dbname = '${DB_NAME}';
\$username = '${APP_DB_USER}';
\$password = '${APP_DB_PASS}';
\$port = 3306;
PHP
sudo mv /tmp/config.php '${APP_PATH}/config.php'"

echo "[5/6] Test app endpointov"
curl -s "http://${WEB_PUBLIC_IP}/index.html" | sed -n '1,120p'
curl -s -X POST -d "element=jabolka&kolicina=3" "http://${WEB_PUBLIC_IP}/vstavi.php" | sed -n '1,220p'
curl -s "http://${WEB_PUBLIC_IP}/izpis.php" | sed -n '1,260p'

echo "[6/6] Povzetek"
echo "WEB_PUBLIC_IP=${WEB_PUBLIC_IP}"
echo "RDS_ENDPOINT=${RDS_ENDPOINT}"
echo "Aplikacija je povezana na RDS."
