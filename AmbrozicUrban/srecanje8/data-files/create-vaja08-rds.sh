#!/usr/bin/env bash
# VAJA-08 — create-vaja08-rds.sh
# Ustvari RDS MariaDB bazo, SG zanjo in DB subnet group v obstojecem VAJA-07 VPC-ju.
# Po izvedbi zapise vaja08-state.env za teardown.
#
# Uporaba:
#   RDS_MASTER_PASSWORD='…' bash create-vaja08-rds.sh
#
# Avtor: Urban Ambrozic

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STATE_V07="${SCRIPT_DIR}/../VAJA-07/vaja07-state.env"
STATE_V08="${SCRIPT_DIR}/vaja08-state.env"

: "${RDS_MASTER_PASSWORD:?Nastavi RDS_MASTER_PASSWORD v okolju}"

if [[ ! -f "$STATE_V07" ]]; then
    echo "Manjka $STATE_V07 — najprej preveri VAJA-07 stanje."
    exit 1
fi
# shellcheck disable=SC1090
source "$STATE_V07"

# vaja08 viri
SG_RDS_NAME="vaja08-sg-rds"
SUBNET_GROUP_NAME="vaja08-subnet-group"
RDS_ID="vaja08-rds"
DB_ENGINE="mariadb"
DB_ENGINE_VERSION="10.11"
DB_INSTANCE_CLASS="db.t3.micro"
DB_STORAGE_GB=20
DB_MASTER_USER="admin"

echo ">>> [1/6] Ustvarjam varnostno skupino $SG_RDS_NAME v $VPC_ID"
SG_RDS_ID=$(aws ec2 create-security-group \
    --group-name "$SG_RDS_NAME" \
    --description "VAJA-08 SG for RDS MariaDB" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SG_RDS_NAME}]" \
    --query 'GroupId' --output text)
echo "    SG_RDS_ID=$SG_RDS_ID"

echo ">>> [2/6] Ustvarjam DB subnet group $SUBNET_GROUP_NAME (Sub2 + Sub3)"
aws rds create-db-subnet-group \
    --db-subnet-group-name "$SUBNET_GROUP_NAME" \
    --db-subnet-group-description "VAJA-08 subnet group (Sub2+Sub3, privatna)" \
    --subnet-ids "$SUB2_ID" "$SUB3_ID" \
    --region "$REGION" \
    --tags "Key=Name,Value=$SUBNET_GROUP_NAME" \
    > /dev/null
echo "    Subnet group ustvarjena."

echo ">>> [3/6] Dodajam inbound pravilo 3306 iz $SG_WEB_ID v $SG_RDS_ID"
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_RDS_ID" \
    --protocol tcp \
    --port 3306 \
    --source-group "$SG_WEB_ID" \
    --region "$REGION" \
    > /dev/null
echo "    Pravilo dodano."

echo ">>> [4/6] Ustvarjam RDS instanco $RDS_ID (MariaDB $DB_ENGINE_VERSION, $DB_INSTANCE_CLASS, $DB_STORAGE_GB GB)"
aws rds create-db-instance \
    --db-instance-identifier "$RDS_ID" \
    --db-instance-class "$DB_INSTANCE_CLASS" \
    --engine "$DB_ENGINE" \
    --engine-version "$DB_ENGINE_VERSION" \
    --allocated-storage "$DB_STORAGE_GB" \
    --storage-type gp2 \
    --master-username "$DB_MASTER_USER" \
    --master-user-password "$RDS_MASTER_PASSWORD" \
    --vpc-security-group-ids "$SG_RDS_ID" \
    --db-subnet-group-name "$SUBNET_GROUP_NAME" \
    --no-publicly-accessible \
    --backup-retention-period 0 \
    --no-multi-az \
    --no-auto-minor-version-upgrade \
    --region "$REGION" \
    --tags "Key=Name,Value=$RDS_ID" \
    > /dev/null
echo "    Zahteva poslana."

echo ">>> [5/6] Cakam na status 'available' (obicajno 5–10 min)…"
aws rds wait db-instance-available --db-instance-identifier "$RDS_ID" --region "$REGION"
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_ID" \
    --region "$REGION" \
    --query 'DBInstances[0].Endpoint.Address' --output text)
echo "    RDS_ENDPOINT=$RDS_ENDPOINT"

echo ">>> [6/6] Zapisujem stanje v $STATE_V08"
cat > "$STATE_V08" <<EOF
# VAJA-08 — stanje infrastrukture (generirano $(date --iso-8601=seconds))
REGION=$REGION
VPC_ID=$VPC_ID
SG_RDS_ID=$SG_RDS_ID
SG_RDS_NAME=$SG_RDS_NAME
SUBNET_GROUP_NAME=$SUBNET_GROUP_NAME
RDS_ID=$RDS_ID
RDS_ENDPOINT=$RDS_ENDPOINT
DB_MASTER_USER=$DB_MASTER_USER
DB_ENGINE=$DB_ENGINE
DB_ENGINE_VERSION=$DB_ENGINE_VERSION
EOF
echo "    Stanje zapisano."

echo ""
echo ">>> Zakljuceno. RDS dostopen na $RDS_ENDPOINT:3306 (interno v VPC)."
