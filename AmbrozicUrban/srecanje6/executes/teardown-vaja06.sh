#!/usr/bin/env bash
#
# VAJA-06 — Čiščenje AWS infrastrukture (obratni vrstni red kot create).
#   Bere vaja06-state.env, ki ga je pustil create-vaja06-infra.sh.
#   Idempotentno: če vir ne obstaja (ali je že izbrisan), ukaz preskočimo.
#
# Uporaba: ./teardown-vaja06.sh
#
# Avtor: Urban Ambrožič

set -uo pipefail  # brez -e, ker dovolimo posamezne failurje

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
STATE_FILE="${SCRIPT_DIR}/vaja06-state.env"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "Ne najdem $STATE_FILE — infrastruktura verjetno ni bila ustvarjena z create-vaja06-infra.sh." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

try() {
    # Poženi ukaz, ignoriraj napake "NotFound" in podobne — teardown mora teči naprej.
    "$@" 2>&1 || true
}

echo ">>> [1/9] Terminacija EC2 instance ${INSTANCE_ID:-?}"
if [[ -n "${INSTANCE_ID:-}" ]]; then
    try aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" > /dev/null
    echo "    Čakam terminated ..."
    try aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"
fi

echo ">>> [2/9] Sprostitev Elastic IP ${EIP_ADDRESS:-?}"
if [[ -n "${EIP_ALLOC_ID:-}" ]]; then
    try aws ec2 release-address --region "$REGION" --allocation-id "$EIP_ALLOC_ID"
fi

echo ">>> [3/9] Brisanje SG ${SG_DB_ID:-?} (db)"
if [[ -n "${SG_DB_ID:-}" ]]; then
    try aws ec2 delete-security-group --region "$REGION" --group-id "$SG_DB_ID"
fi

echo ">>> [4/9] Brisanje SG ${SG_WEB_ID:-?} (web)"
if [[ -n "${SG_WEB_ID:-}" ]]; then
    try aws ec2 delete-security-group --region "$REGION" --group-id "$SG_WEB_ID"
fi

echo ">>> [5/9] Disassociate + brisanje route table ${RTB_ID:-?}"
if [[ -n "${RTB_ASSOC_ID:-}" ]]; then
    try aws ec2 disassociate-route-table --region "$REGION" --association-id "$RTB_ASSOC_ID"
fi
if [[ -n "${RTB_ID:-}" ]]; then
    try aws ec2 delete-route-table --region "$REGION" --route-table-id "$RTB_ID"
fi

echo ">>> [6/9] Detach + brisanje IGW ${IGW_ID:-?}"
if [[ -n "${IGW_ID:-}" && -n "${VPC_ID:-}" ]]; then
    try aws ec2 detach-internet-gateway --region "$REGION" \
        --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
fi
if [[ -n "${IGW_ID:-}" ]]; then
    try aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID"
fi

echo ">>> [7/9] Brisanje podomrežij"
if [[ -n "${PUBLIC_SUBNET_ID:-}" ]]; then
    try aws ec2 delete-subnet --region "$REGION" --subnet-id "$PUBLIC_SUBNET_ID"
fi
if [[ -n "${PRIVATE_SUBNET_ID:-}" ]]; then
    try aws ec2 delete-subnet --region "$REGION" --subnet-id "$PRIVATE_SUBNET_ID"
fi

echo ">>> [8/9] Brisanje VPC ${VPC_ID:-?}"
if [[ -n "${VPC_ID:-}" ]]; then
    try aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID"
fi

echo ">>> [9/9] Brisanje ključnega para in lokalnega .pem"
if [[ -n "${KEY_NAME:-}" ]]; then
    try aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME"
fi
if [[ -n "${KEY_FILE:-}" && -f "$KEY_FILE" ]]; then
    rm -f "$KEY_FILE"
    echo "    Lokalni $KEY_FILE izbrisan."
fi

echo ""
echo "========================================="
echo "Preverjanje ostankov (filter Name=vaja06-*):"
echo ""
echo "VPC-ji:"
aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=${PREFIX:-vaja06}-*" \
    --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output table 2>/dev/null || true
echo ""
echo "EC2 instance (running ali pending):"
aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=${PREFIX:-vaja06}-*" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' --output table 2>/dev/null || true
echo ""
echo "Če sta tabeli prazni, je teardown zaključen."
echo "========================================="

# Čiščenje stanja
mv "$STATE_FILE" "${STATE_FILE}.bak" 2>/dev/null || true
echo "vaja06-state.env preimenovan v vaja06-state.env.bak"
