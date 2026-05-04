#!/bin/bash
set -e

apt update -y
apt upgrade -y
apt install apache2 -y
systemctl enable --now apache2
echo "<h1>Apache na EC2 deluje</h1>" > /var/www/html/index.html
