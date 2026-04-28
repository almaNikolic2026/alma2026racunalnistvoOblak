#!/usr/bin/env bash
set -euo pipefail

RDS_HOST="${RDS_HOST:-}"
RDS_DB="${RDS_DB:-}"
RDS_USER="${RDS_USER:-}"
RDS_PASS="${RDS_PASS:-}"
RELEASE_SHA="${RELEASE_SHA:-manual}"

if [[ -z "${RDS_HOST}" || -z "${RDS_DB}" || -z "${RDS_USER}" || -z "${RDS_PASS}" ]]; then
  echo "ERROR: Missing required RDS variables."
  exit 1
fi

if ! command -v mariadb >/dev/null 2>&1; then
  echo "mariadb client missing, installing..."
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y mariadb-client >/dev/null
fi

export MYSQL_PWD="${RDS_PASS}"

mariadb -h "${RDS_HOST}" -u "${RDS_USER}" <<SQL
CREATE DATABASE IF NOT EXISTS ${RDS_DB};
USE ${RDS_DB};

CREATE TABLE IF NOT EXISTS nakup (
  id INT AUTO_INCREMENT PRIMARY KEY,
  element VARCHAR(255) NOT NULL,
  kolicina INT NOT NULL
);

CREATE TABLE IF NOT EXISTS schema_migrations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  release_sha VARCHAR(64) NOT NULL,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

SET @col_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = '${RDS_DB}'
    AND TABLE_NAME = 'nakup'
    AND COLUMN_NAME = 'deployed_at'
);

SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE nakup ADD COLUMN deployed_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP',
  'SELECT 1'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

INSERT INTO schema_migrations (release_sha) VALUES ('${RELEASE_SHA}');
SQL

echo "Migration complete for ${RELEASE_SHA}"
