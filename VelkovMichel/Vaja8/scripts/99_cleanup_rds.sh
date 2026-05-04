#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-central-1}"
DB_INSTANCE_ID="${DB_INSTANCE_ID:-v7-michel-rds-db}"
RDS_SG_NAME="${RDS_SG_NAME:-v7-michel-rds-sg}"
DB_SUBNET_GROUP="${DB_SUBNET_GROUP:-v7-michel-db-subnet-group}"
VPC_ID="${VPC_ID:-}"

if [[ -f "./rds_outputs.env" ]]; then
  # shellcheck disable=SC1091
  source ./rds_outputs.env
fi

if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
  VPC_ID="$(aws ec2 describe-security-groups --region "${AWS_REGION}" \
    --filters "Name=group-name,Values=${RDS_SG_NAME}" \
    --query "SecurityGroups[0].VpcId" --output text 2>/dev/null || true)"
fi

echo "Brisem RDS instanco: ${DB_INSTANCE_ID}"
aws rds delete-db-instance \
  --region "${AWS_REGION}" \
  --db-instance-identifier "${DB_INSTANCE_ID}" \
  --skip-final-snapshot >/dev/null 2>&1 || true

aws rds wait db-instance-deleted \
  --region "${AWS_REGION}" \
  --db-instance-identifier "${DB_INSTANCE_ID}" >/dev/null 2>&1 || true

if [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" ]]; then
  RDS_SG_ID="$(aws ec2 describe-security-groups --region "${AWS_REGION}" \
    --filters "Name=group-name,Values=${RDS_SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)"

  if [[ -n "${RDS_SG_ID}" && "${RDS_SG_ID}" != "None" ]]; then
    echo "Brisem RDS SG: ${RDS_SG_ID}"
    aws ec2 delete-security-group --region "${AWS_REGION}" --group-id "${RDS_SG_ID}" >/dev/null 2>&1 || true
  fi
fi

echo "Brisem DB subnet group: ${DB_SUBNET_GROUP}"
aws rds delete-db-subnet-group \
  --region "${AWS_REGION}" \
  --db-subnet-group-name "${DB_SUBNET_GROUP}" >/dev/null 2>&1 || true

echo "Cleanup zakljucen."
