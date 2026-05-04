#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-central-1}"
PREFIX="${PREFIX:-v7-michel}"
DB_ENGINE="${DB_ENGINE:-mysql}"
DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-db.t3.micro}"
DB_STORAGE_GB="${DB_STORAGE_GB:-20}"
DB_NAME="${DB_NAME:-nakupni_seznam}"
DB_ADMIN_USER="${DB_ADMIN_USER:-admin}"
DB_ADMIN_PASS="${DB_ADMIN_PASS:-}"
DB_INSTANCE_ID="${DB_INSTANCE_ID:-${PREFIX}-rds-db}"
RDS_SG_NAME="${RDS_SG_NAME:-${PREFIX}-rds-sg}"
DB_SUBNET_GROUP="${DB_SUBNET_GROUP:-${PREFIX}-db-subnet-group}"
WEB_INSTANCE_NAME="${WEB_INSTANCE_NAME:-${PREFIX}-ec2-web}"

if [[ -z "${DB_ADMIN_PASS}" ]]; then
  echo "ERROR: DB_ADMIN_PASS ni nastavljen."
  echo "Primer: export DB_ADMIN_PASS='MojeVarnoGeslo123!'"
  exit 1
fi

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "${value}" || "${value}" == "None" || "${value}" == "null" ]]; then
    echo "ERROR: manjkajoca vrednost: ${name}"
    exit 1
  fi
}

echo "[1/8] Iscem WEB instanco: ${WEB_INSTANCE_NAME}"
WEB_INSTANCE_ID="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters "Name=tag:Name,Values=${WEB_INSTANCE_NAME}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "sort_by(Reservations[].Instances[], &LaunchTime)[-1].InstanceId" \
  --output text)"

if [[ -z "${WEB_INSTANCE_ID}" || "${WEB_INSTANCE_ID}" == "None" || "${WEB_INSTANCE_ID}" == "null" ]]; then
  echo "ERROR: manjkajoca vrednost: WEB_INSTANCE_ID"
  echo "Hint: preveri Name tag web instance (trenutno se isce: ${WEB_INSTANCE_NAME})."
  echo "Hint: aws ec2 describe-instances --region ${AWS_REGION} --filters Name=instance-state-name,Values=pending,running,stopping,stopped --query \"Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Id:InstanceId,State:State.Name}\" --output table"
  exit 1
fi

WEB_INSTANCE_STATE="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --instance-ids "${WEB_INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text)"

if [[ "${WEB_INSTANCE_STATE}" == "stopping" ]]; then
  echo "WEB instanca je v stanju stopping, cakam na stopped ..."
  aws ec2 wait instance-stopped --region "${AWS_REGION}" --instance-ids "${WEB_INSTANCE_ID}"
  WEB_INSTANCE_STATE="stopped"
fi

if [[ "${WEB_INSTANCE_STATE}" == "stopped" ]]; then
  echo "WEB instanca je stopped, izvajam start ..."
  aws ec2 start-instances --region "${AWS_REGION}" --instance-ids "${WEB_INSTANCE_ID}" >/dev/null
  aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${WEB_INSTANCE_ID}"
fi

VPC_ID="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --instance-ids "${WEB_INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].VpcId" \
  --output text)"
APP_SG_ID="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --instance-ids "${WEB_INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
  --output text)"
require_value "VPC_ID" "${VPC_ID}"
require_value "APP_SG_ID" "${APP_SG_ID}"

echo "[2/8] Iscem private subneta"
DB_SUBNET_A="$(aws ec2 describe-subnets \
  --region "${AWS_REGION}" \
  --filters "Name=tag:Name,Values=${PREFIX}-sub2-private" \
  --query "Subnets[0].SubnetId" \
  --output text)"
DB_SUBNET_B="$(aws ec2 describe-subnets \
  --region "${AWS_REGION}" \
  --filters "Name=tag:Name,Values=${PREFIX}-sub3-private" \
  --query "Subnets[0].SubnetId" \
  --output text)"
require_value "DB_SUBNET_A" "${DB_SUBNET_A}"
require_value "DB_SUBNET_B" "${DB_SUBNET_B}"

echo "[3/8] RDS Security Group"
RDS_SG_ID="$(aws ec2 describe-security-groups \
  --region "${AWS_REGION}" \
  --filters "Name=group-name,Values=${RDS_SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" \
  --output text)"

if [[ -z "${RDS_SG_ID}" || "${RDS_SG_ID}" == "None" ]]; then
  RDS_SG_ID="$(aws ec2 create-security-group \
    --region "${AWS_REGION}" \
    --group-name "${RDS_SG_NAME}" \
    --description "RDS SG for Vaja8" \
    --vpc-id "${VPC_ID}" \
    --query "GroupId" --output text)"
fi
require_value "RDS_SG_ID" "${RDS_SG_ID}"

aws ec2 authorize-security-group-ingress \
  --region "${AWS_REGION}" \
  --group-id "${RDS_SG_ID}" \
  --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":3306,\"ToPort\":3306,\"UserIdGroupPairs\":[{\"GroupId\":\"${APP_SG_ID}\"}]}]" \
  >/dev/null 2>&1 || true

echo "[4/8] DB subnet group"
EXISTING_SUBNET_GROUP="$(aws rds describe-db-subnet-groups \
  --region "${AWS_REGION}" \
  --db-subnet-group-name "${DB_SUBNET_GROUP}" \
  --query "DBSubnetGroups[0].DBSubnetGroupName" \
  --output text 2>/dev/null || true)"

if [[ -z "${EXISTING_SUBNET_GROUP}" || "${EXISTING_SUBNET_GROUP}" == "None" ]]; then
  aws rds create-db-subnet-group \
    --region "${AWS_REGION}" \
    --db-subnet-group-name "${DB_SUBNET_GROUP}" \
    --db-subnet-group-description "Subnet group for Vaja8 RDS" \
    --subnet-ids "${DB_SUBNET_A}" "${DB_SUBNET_B}" >/dev/null
fi

echo "[5/8] RDS instance"
EXISTING_DB="$(aws rds describe-db-instances \
  --region "${AWS_REGION}" \
  --db-instance-identifier "${DB_INSTANCE_ID}" \
  --query "DBInstances[0].DBInstanceIdentifier" \
  --output text 2>/dev/null || true)"

if [[ -z "${EXISTING_DB}" || "${EXISTING_DB}" == "None" ]]; then
  aws rds create-db-instance \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${DB_INSTANCE_ID}" \
    --engine "${DB_ENGINE}" \
    --db-instance-class "${DB_INSTANCE_CLASS}" \
    --allocated-storage "${DB_STORAGE_GB}" \
    --master-username "${DB_ADMIN_USER}" \
    --master-user-password "${DB_ADMIN_PASS}" \
    --vpc-security-group-ids "${RDS_SG_ID}" \
    --db-subnet-group-name "${DB_SUBNET_GROUP}" \
    --no-publicly-accessible \
    --db-name "${DB_NAME}" \
    --backup-retention-period 0 \
    --no-multi-az >/dev/null
fi

echo "[6/8] Cakam, da RDS postane available"
aws rds wait db-instance-available \
  --region "${AWS_REGION}" \
  --db-instance-identifier "${DB_INSTANCE_ID}"

RDS_ENDPOINT="$(aws rds describe-db-instances \
  --region "${AWS_REGION}" \
  --db-instance-identifier "${DB_INSTANCE_ID}" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)"
require_value "RDS_ENDPOINT" "${RDS_ENDPOINT}"

echo "[7/8] Izvoz izhodnih vrednosti"
cat > rds_outputs.env <<EOF
export AWS_REGION='${AWS_REGION}'
export PREFIX='${PREFIX}'
export WEB_INSTANCE_NAME='${WEB_INSTANCE_NAME}'
export WEB_INSTANCE_ID='${WEB_INSTANCE_ID}'
export VPC_ID='${VPC_ID}'
export APP_SG_ID='${APP_SG_ID}'
export DB_SUBNET_A='${DB_SUBNET_A}'
export DB_SUBNET_B='${DB_SUBNET_B}'
export RDS_SG_NAME='${RDS_SG_NAME}'
export RDS_SG_ID='${RDS_SG_ID}'
export DB_SUBNET_GROUP='${DB_SUBNET_GROUP}'
export DB_INSTANCE_ID='${DB_INSTANCE_ID}'
export DB_NAME='${DB_NAME}'
export DB_ADMIN_USER='${DB_ADMIN_USER}'
export DB_ADMIN_PASS='${DB_ADMIN_PASS}'
export RDS_ENDPOINT='${RDS_ENDPOINT}'
EOF

echo "[8/8] Povzetek"
echo "WEB_INSTANCE_ID=${WEB_INSTANCE_ID}"
echo "VPC_ID=${VPC_ID}"
echo "APP_SG_ID=${APP_SG_ID}"
echo "RDS_SG_ID=${RDS_SG_ID}"
echo "DB_SUBNET_GROUP=${DB_SUBNET_GROUP}"
echo "DB_INSTANCE_ID=${DB_INSTANCE_ID}"
echo "RDS_ENDPOINT=${RDS_ENDPOINT}"
echo
echo "OK: rds_outputs.env je ustvarjen."
