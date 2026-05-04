#!/usr/bin/env bash
# VAJA-08 — teardown-vaja08.sh
# Izbrise RDS instanco, subnet group in SG; terminira EC2-2 + EC2-3 (niso vec potrebna, RDS nadomesti bazo);
# ustavi EC2-1 (lahko se uporabi v naslednjih vajah).
# Nepovratno — preveri, da si vse screenshote in poročilo zakljucil.
#
# EIP se NE sprosti — o njem odloca Urban rocno po potrebi.
#
# Uporaba:
#   bash teardown-vaja08.sh
#
# Avtor: Urban Ambrozic

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STATE_V07="${SCRIPT_DIR}/../VAJA-07/vaja07-state.env"
STATE_V08="${SCRIPT_DIR}/vaja08-state.env"

if [[ ! -f "$STATE_V07" ]] || [[ ! -f "$STATE_V08" ]]; then
    echo "Manjka state file ($STATE_V07 ali $STATE_V08)."
    exit 1
fi
# shellcheck disable=SC1090
source "$STATE_V07"
# shellcheck disable=SC1090
source "$STATE_V08"

echo ">>> [1/6] Brisem RDS instanco $RDS_ID (skip-final-snapshot)"
aws rds delete-db-instance \
    --db-instance-identifier "$RDS_ID" \
    --skip-final-snapshot \
    --delete-automated-backups \
    --region "$REGION" \
    > /dev/null || true
echo "    Cakam na dokoncanje brisanja (5–10 min)…"
aws rds wait db-instance-deleted --db-instance-identifier "$RDS_ID" --region "$REGION" || true

echo ">>> [2/6] Brisem DB subnet group $SUBNET_GROUP_NAME"
aws rds delete-db-subnet-group \
    --db-subnet-group-name "$SUBNET_GROUP_NAME" \
    --region "$REGION" \
    || true

echo ">>> [3/6] Brisem varnostno skupino $SG_RDS_ID"
aws ec2 delete-security-group --group-id "$SG_RDS_ID" --region "$REGION" || true

echo ">>> [4/6] Terminiram EC2-2 ($EC2_DB1_ID) in EC2-3 ($EC2_DB2_ID)"
aws ec2 terminate-instances --instance-ids "$EC2_DB1_ID" "$EC2_DB2_ID" --region "$REGION" > /dev/null || true
aws ec2 wait instance-terminated --instance-ids "$EC2_DB1_ID" "$EC2_DB2_ID" --region "$REGION" || true

echo ">>> [5/6] Ustavljam EC2-1 ($EC2_WEB_ID)"
aws ec2 stop-instances --instance-ids "$EC2_WEB_ID" --region "$REGION" > /dev/null || true
aws ec2 wait instance-stopped --instance-ids "$EC2_WEB_ID" --region "$REGION" || true

echo ">>> [6/6] Preverjam koncno stanje"
echo "--- RDS ---"
aws rds describe-db-instances --region "$REGION" \
    --query 'DBInstances[?DBInstanceIdentifier==`'"$RDS_ID"'`].[DBInstanceIdentifier,DBInstanceStatus]' \
    --output table || echo "    (RDS izbrisan)"
echo "--- EC2 ---"
aws ec2 describe-instances --instance-ids "$EC2_WEB_ID" "$EC2_DB1_ID" "$EC2_DB2_ID" \
    --region "$REGION" \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
    --output table

echo ""
echo ">>> Teardown zakljucen. EIP $EIP_ADDRESS in SG-ji iz VAJA-07 ostajajo."
