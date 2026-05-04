#!/usr/bin/env bash
#
# VAJA-06 — Postavitev Apache + PHP + MariaDB na EC2 instanci.
#   Teče NA EC2 instanci (pognan s sudo). Pred zagonom morajo biti v isti mapi:
#     setup-db.sql       (shema + seed)
#     webapp/index.php   + webapp/db.php
#
# Uporaba (na EC2):
#   sudo bash setup-server.sh
#
# Avtor: Urban Ambrožič

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $EUID -ne 0 ]]; then
    echo "Skripto je treba pognati kot root (uporabi sudo)." >&2
    exit 1
fi

MARIADB_CNF="/etc/mysql/mariadb.conf.d/50-server.cnf"
WEBROOT="/var/www/html"

echo ">>> [1/7] Osvežujem seznam paketov (apt update)"
apt-get update -y > /dev/null

echo ">>> [2/7] Nameščam apache2, php, php-mysql, mariadb-server"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 php php-mysql php-mbstring mariadb-server > /dev/null

echo ">>> [3/7] Vklapljam in zaganjam storitvi"
systemctl enable --now apache2 > /dev/null
systemctl enable --now mariadb > /dev/null

echo ">>> [4/7] Konfiguriram MariaDB bind-address = 0.0.0.0"
if [[ -f "$MARIADB_CNF" ]]; then
    sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$MARIADB_CNF"
    # Če vrstice ni bilo (npr. zakomentirana drugače), jo dodaj eksplicitno.
    if ! grep -q '^bind-address' "$MARIADB_CNF"; then
        sed -i '/^\[mysqld\]/a bind-address = 0.0.0.0' "$MARIADB_CNF"
    fi
else
    echo "    Opozorilo: $MARIADB_CNF ne obstaja — preskakujem." >&2
fi

echo ">>> [5/7] Ponovni zagon MariaDB"
systemctl restart mariadb

echo ">>> [6/7] Uvoz setup-db.sql (baza AlmaMater, tabela student, uporabnik dusan)"
if [[ ! -f "${SCRIPT_DIR}/setup-db.sql" ]]; then
    echo "    Napaka: setup-db.sql ne obstaja v $SCRIPT_DIR" >&2
    exit 1
fi
mariadb < "${SCRIPT_DIR}/setup-db.sql"

echo ">>> [7/7] Deploy spletne aplikacije v $WEBROOT"
if [[ ! -d "${SCRIPT_DIR}/webapp" ]]; then
    echo "    Napaka: mapa webapp/ ne obstaja v $SCRIPT_DIR" >&2
    exit 1
fi
rm -f "${WEBROOT}/index.html"
cp -r "${SCRIPT_DIR}/webapp/." "${WEBROOT}/"
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type f -exec chmod 644 {} \;
find "$WEBROOT" -type d -exec chmod 755 {} \;

echo ""
echo "========================================="
echo "Postavitev uspešna."
echo "  Spletni strežnik: $(systemctl is-active apache2)"
echo "  MariaDB:          $(systemctl is-active mariadb)"
echo "  Testna poizvedba: mariadb -u urban -purban -e 'SELECT * FROM AlmaMater.student;'"
echo "========================================="
