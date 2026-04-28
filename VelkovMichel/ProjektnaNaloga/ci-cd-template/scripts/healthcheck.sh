#!/usr/bin/env bash
set -euo pipefail

APP_URL="${APP_URL:-http://localhost}"

echo "Health check: ${APP_URL}/index.html"
curl --fail --silent --show-error "${APP_URL}/index.html" >/dev/null

echo "Health check: ${APP_URL}/izpis.php"
IZPIS_BODY="$(curl --fail --silent --show-error "${APP_URL}/izpis.php")"

if echo "${IZPIS_BODY}" | grep -Eq 'Napaka baze|DB1_PRIVATE_IP'; then
	echo "ERROR: izpis.php still shows a database error or placeholder host."
	exit 1
fi

echo "Health checks passed."
