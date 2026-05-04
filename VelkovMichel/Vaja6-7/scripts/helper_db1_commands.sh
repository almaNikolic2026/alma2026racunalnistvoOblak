#!/usr/bin/env bash
# Helper script executed on DB1 instance.
# Called by scripts/02_configure_db1.sh.

set -euo pipefail

sudo apt update -y
sudo apt install -y mariadb-server
sudo systemctl enable mariadb
sudo systemctl start mariadb
sudo systemctl status mariadb --no-pager

# Allow MariaDB connections from web EC2 inside VPC.
sudo sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl restart mariadb

# Determine how to connect as root (socket auth before password change, password auth after).
MYSQL_ROOT_CMD="sudo mysql"
if ! sudo mysql -e "SELECT 1" >/dev/null 2>&1; then
	MYSQL_ROOT_CMD="sudo mysql -uroot -pRootPass123!"
fi

# Configure root password, DB schema, app user, and test data in one SQL session.
$MYSQL_ROOT_CMD <<'SQL'
ALTER USER 'root'@'localhost' IDENTIFIED BY 'RootPass123!';

CREATE DATABASE IF NOT EXISTS nakupni_seznam;
USE nakupni_seznam;

CREATE TABLE IF NOT EXISTS nakup (
	id INT AUTO_INCREMENT PRIMARY KEY,
	element VARCHAR(100) NOT NULL,
	kolicina INT NOT NULL
);

INSERT INTO nakup (element, kolicina) VALUES
('kruh', 1),
('mleko', 2);

CREATE USER IF NOT EXISTS 'nakup_app'@'192.168.%' IDENTIFIED BY 'ChangeThisStrongPass123!';
GRANT ALL PRIVILEGES ON nakupni_seznam.* TO 'nakup_app'@'192.168.%';
FLUSH PRIVILEGES;
SQL

echo "DB1 configuration complete"
