#!/usr/bin/env bash
# Cleanup script for old lab resources.
# Deletes resources with name prefixes only (safer than global delete).
# Usage:
#   chmod +x scripts/00_cleanup_old_resources.sh
#   scripts/00_cleanup_old_resources.sh

set -euo pipefail

REGION="eu-central-1"
PREFIXES=("alma-" "v7-michel")

for cmd in aws jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required" >&2
    exit 1
  fi
done

echo "This will delete EC2/VPC related resources tagged with prefixes: ${PREFIXES[*]} in $REGION"
read -r -p "Type YES to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Cancelled"
  exit 0
fi

match_name() {
  local name="$1"
  for p in "${PREFIXES[@]}"; do
    if [[ "$name" == "$p"* ]]; then
      return 0
    fi
  done
  return 1
}

# 1) Find prefixed VPCs by Name tag
mapfile -t VPCS < <(aws ec2 describe-vpcs --region "$REGION" --output json | jq -r '
  .Vpcs[]
  | {id: .VpcId, name: ((.Tags // []) | map(select(.Key=="Name") | .Value) | .[0] // "")}
  | select(.name|startswith("alma-") or startswith("v7-michel"))
  | .id')

# 2) For each VPC: terminate instances -> delete NAT -> IGW -> routes -> subnets -> SG -> VPC
for vpc in "${VPCS[@]:-}"; do
  [[ -z "$vpc" ]] && continue
  echo "Cleaning VPC: $vpc"

  mapfile -t INSTANCE_IDS < <(aws ec2 describe-instances --region "$REGION" \
    --filters Name=vpc-id,Values="$vpc" Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t ' '\n\n' | sed '/^$/d')

  if (( ${#INSTANCE_IDS[@]} > 0 )); then
    aws ec2 terminate-instances --region "$REGION" --instance-ids "${INSTANCE_IDS[@]}" >/dev/null || true
    aws ec2 wait instance-terminated --region "$REGION" --instance-ids "${INSTANCE_IDS[@]}" || true
  fi

  mapfile -t NAT_IDS < <(aws ec2 describe-nat-gateways --region "$REGION" \
    --filter Name=vpc-id,Values="$vpc" Name=state,Values=available,pending,failed \
    --query 'NatGateways[].NatGatewayId' --output text | tr '\t ' '\n\n' | sed '/^$/d')

  mapfile -t EIP_ALLOCS < <(aws ec2 describe-nat-gateways --region "$REGION" \
    --filter Name=vpc-id,Values="$vpc" Name=state,Values=available,pending,failed \
    --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text | tr '\t ' '\n\n' | sed '/^$/d')

  for nat in "${NAT_IDS[@]:-}"; do
    [[ -z "$nat" ]] && continue
    aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$nat" >/dev/null || true
  done
  if (( ${#NAT_IDS[@]} > 0 )); then
    aws ec2 wait nat-gateway-deleted --region "$REGION" --nat-gateway-ids "${NAT_IDS[@]}" || true
  fi

  for alloc in "${EIP_ALLOCS[@]:-}"; do
    [[ -z "$alloc" || "$alloc" == "None" ]] && continue
    aws ec2 release-address --region "$REGION" --allocation-id "$alloc" >/dev/null || true
  done

  mapfile -t IGW_IDS < <(aws ec2 describe-internet-gateways --region "$REGION" \
    --filters Name=attachment.vpc-id,Values="$vpc" \
    --query 'InternetGateways[].InternetGatewayId' --output text | tr '\t ' '\n\n' | sed '/^$/d')

  for igw in "${IGW_IDS[@]:-}"; do
    [[ -z "$igw" ]] && continue
    aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$igw" --vpc-id "$vpc" >/dev/null || true
    aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$igw" >/dev/null || true
  done

  mapfile -t RT_IDS < <(aws ec2 describe-route-tables --region "$REGION" \
    --filters Name=vpc-id,Values="$vpc" \
    --query 'RouteTables[?Associations[?Main==`false`]].RouteTableId' --output text | tr '\t ' '\n\n' | sed '/^$/d')

  for rt in "${RT_IDS[@]:-}"; do
    [[ -z "$rt" ]] && continue
    mapfile -t ASSOC_IDS < <(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$rt" \
      --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' --output text | tr '\t ' '\n\n' | sed '/^$/d')
    for assoc in "${ASSOC_IDS[@]:-}"; do
      [[ -z "$assoc" ]] && continue
      aws ec2 disassociate-route-table --region "$REGION" --association-id "$assoc" >/dev/null || true
    done
    aws ec2 delete-route-table --region "$REGION" --route-table-id "$rt" >/dev/null || true
  done

  mapfile -t SUBNET_IDS < <(aws ec2 describe-subnets --region "$REGION" \
    --filters Name=vpc-id,Values="$vpc" \
    --query 'Subnets[].SubnetId' --output text | tr '\t ' '\n\n' | sed '/^$/d')

  for sn in "${SUBNET_IDS[@]:-}"; do
    [[ -z "$sn" ]] && continue
    aws ec2 delete-subnet --region "$REGION" --subnet-id "$sn" >/dev/null || true
  done

  mapfile -t SG_IDS < <(aws ec2 describe-security-groups --region "$REGION" \
    --filters Name=vpc-id,Values="$vpc" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text | tr '\t ' '\n\n' | sed '/^$/d')

  for sg in "${SG_IDS[@]:-}"; do
    [[ -z "$sg" ]] && continue
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg" >/dev/null || true
  done

  aws ec2 delete-vpc --region "$REGION" --vpc-id "$vpc" >/dev/null || true
done

# 3) Delete key pairs by prefix
for key_name in $(aws ec2 describe-key-pairs --region "$REGION" --query 'KeyPairs[].KeyName' --output text); do
  if match_name "$key_name"; then
    aws ec2 delete-key-pair --region "$REGION" --key-name "$key_name" >/dev/null || true
  fi
done

# 4) Delete S3 buckets by prefix (force)
for bucket in $(aws s3api list-buckets --query 'Buckets[].Name' --output text); do
  if match_name "$bucket"; then
    aws s3 rb "s3://$bucket" --force || true
  fi
done

echo "Cleanup finished (prefixed resources only)."
