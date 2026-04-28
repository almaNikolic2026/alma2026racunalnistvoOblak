#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-/var/www/html}"
RELEASES_DIR="${RELEASES_DIR:-/var/www/releases}"
CURRENT_LINK="${CURRENT_LINK:-/var/www/current}"
LAST_FILE="${RELEASES_DIR}/.last_successful"
PREV_FILE="${RELEASES_DIR}/.previous_successful"

TARGET_RELEASE=""

if [[ -f "${PREV_FILE}" ]]; then
  TARGET_RELEASE="$(sudo cat "${PREV_FILE}")"
else
  TARGET_RELEASE="$(sudo ls -1 "${RELEASES_DIR}" | grep -E '^[0-9]{14}-' | sort | tail -n 2 | head -n 1 || true)"
fi

if [[ -z "${TARGET_RELEASE}" ]]; then
  echo "ERROR: No previous release found for rollback."
  exit 1
fi

TARGET_DIR="${RELEASES_DIR}/${TARGET_RELEASE}"
if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "ERROR: Target rollback release does not exist: ${TARGET_DIR}"
  exit 1
fi

echo "Rolling back to ${TARGET_RELEASE}"
sudo ln -sfn "${TARGET_DIR}" "${CURRENT_LINK}"
sudo rsync -a --delete "${CURRENT_LINK}/" "${APP_PATH}/"
sudo chown -R www-data:www-data "${APP_PATH}"
sudo systemctl restart apache2

echo "${TARGET_RELEASE}" | sudo tee "${LAST_FILE}" >/dev/null
echo "Rollback complete."
