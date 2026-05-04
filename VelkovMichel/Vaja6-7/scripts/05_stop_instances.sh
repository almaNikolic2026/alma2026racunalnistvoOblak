#!/usr/bin/env bash
# Stop (do not delete) Vaja6-7 instances after testing.
# Usage:
#   chmod +x VelkovMichel/Vaja6-7/scripts/05_stop_instances.sh
#   VelkovMichel/Vaja6-7/scripts/05_stop_instances.sh

set -euo pipefail

REGION="eu-central-1"
PREFIX="v7-michel-ec2-"

INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=${PREFIX}*" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)

if [[ -z "$INSTANCE_IDS" ]]; then
  echo "No instances found for prefix $PREFIX"
  exit 0
fi

aws ec2 stop-instances --region "$REGION" --instance-ids $INSTANCE_IDS >/dev/null
aws ec2 wait instance-stopped --region "$REGION" --instance-ids $INSTANCE_IDS

echo "Instances stopped: $INSTANCE_IDS"
