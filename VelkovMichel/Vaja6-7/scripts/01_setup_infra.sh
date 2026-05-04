#!/usr/bin/env bash
# Vaja 6-7 - automatic infrastructure setup (AWS CLI)
# Usage:
#   chmod +x scripts/01_setup_infra.sh
#   scripts/01_setup_infra.sh <MY_IP_CIDR> [AMI_ID]
# Example:
#   scripts/01_setup_infra.sh 89.212.10.5/32

set -euo pipefail

REGION="eu-central-1"
NAME_PREFIX="v7-michel"
KEY_NAME="${NAME_PREFIX}-key"
INSTANCE_TYPE="t3.small"
MY_IP_CIDR="${1:-}"
CUSTOM_AMI_ID="${2:-${AMI_ID:-}}"
DEFAULT_AMI_ID="ami-02daa6fa3fe5f3161"

if [[ -z "$MY_IP_CIDR" ]]; then
  echo "ERROR: Missing MY_IP_CIDR argument (example 89.212.10.5/32)" >&2
  exit 1
fi

for cmd in aws; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required" >&2
    exit 1
  fi
done

AMI_ID="$CUSTOM_AMI_ID"

if [[ -z "$AMI_ID" ]]; then
  AMI_ID="$(aws ssm get-parameter \
    --region "$REGION" \
    --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query 'Parameter.Value' --output text 2>/dev/null || true)"
fi

if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
  AMI_ID="$(aws ec2 describe-images \
    --region "$REGION" \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*" "Name=architecture,Values=x86_64" "Name=state,Values=available" \
    --query "reverse(sort_by(Images,&CreationDate))[0].ImageId" \
    --output text 2>/dev/null || true)"
fi

if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
  AMI_ID="$DEFAULT_AMI_ID"
  echo "WARN: AMI autodetect failed, using fallback AMI: $AMI_ID"
fi

AMI_CHECK="$(aws ec2 describe-images --region "$REGION" --image-ids "$AMI_ID" --query 'Images[0].ImageId' --output text 2>/dev/null || true)"
if [[ -z "$AMI_CHECK" || "$AMI_CHECK" == "None" ]]; then
  echo "ERROR: AMI '$AMI_ID' is not valid in region $REGION" >&2
  echo "Run with explicit AMI: ./scripts/01_setup_infra.sh <MY_IP/32> <AMI_ID>" >&2
  exit 1
fi

echo "Using AMI: $AMI_ID"

# 1) VPC 192.168.0.0/24
VPC_ID="$(aws ec2 create-vpc \
  --region "$REGION" \
  --cidr-block 192.168.0.0/24 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${NAME_PREFIX}-vpc}]" \
  --query 'Vpc.VpcId' --output text)"

aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

# 2) Subnets (/25, /26, /27) in different AZ
SUB1_ID="$(aws ec2 create-subnet \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block 192.168.0.0/25 \
  --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-sub1-public}]" \
  --query 'Subnet.SubnetId' --output text)"

SUB2_ID="$(aws ec2 create-subnet \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block 192.168.0.128/26 \
  --availability-zone ${REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-sub2-private}]" \
  --query 'Subnet.SubnetId' --output text)"

SUB3_ID="$(aws ec2 create-subnet \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block 192.168.0.192/27 \
  --availability-zone ${REGION}c \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME_PREFIX}-sub3-private}]" \
  --query 'Subnet.SubnetId' --output text)"

aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$SUB1_ID" --map-public-ip-on-launch

# 3) IGW + public route table
IGW_ID="$(aws ec2 create-internet-gateway \
  --region "$REGION" \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${NAME_PREFIX}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' --output text)"
aws ec2 attach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

RT_PUBLIC_ID="$(aws ec2 create-route-table \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${NAME_PREFIX}-rt-public}]" \
  --query 'RouteTable.RouteTableId' --output text)"

aws ec2 create-route --region "$REGION" --route-table-id "$RT_PUBLIC_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"
aws ec2 associate-route-table --region "$REGION" --route-table-id "$RT_PUBLIC_ID" --subnet-id "$SUB1_ID" >/dev/null

# 4) NAT + private route table (needed so private EC2 can apt install)
EIP_ALLOC_ID="$(aws ec2 allocate-address --region "$REGION" --domain vpc --query 'AllocationId' --output text)"
NAT_ID="$(aws ec2 create-nat-gateway \
  --region "$REGION" \
  --subnet-id "$SUB1_ID" \
  --allocation-id "$EIP_ALLOC_ID" \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${NAME_PREFIX}-nat}]" \
  --query 'NatGateway.NatGatewayId' --output text)"

aws ec2 wait nat-gateway-available --region "$REGION" --nat-gateway-ids "$NAT_ID"

RT_PRIVATE_ID="$(aws ec2 create-route-table \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${NAME_PREFIX}-rt-private}]" \
  --query 'RouteTable.RouteTableId' --output text)"

aws ec2 create-route --region "$REGION" --route-table-id "$RT_PRIVATE_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID"
aws ec2 associate-route-table --region "$REGION" --route-table-id "$RT_PRIVATE_ID" --subnet-id "$SUB2_ID" >/dev/null
aws ec2 associate-route-table --region "$REGION" --route-table-id "$RT_PRIVATE_ID" --subnet-id "$SUB3_ID" >/dev/null

# 5) Key pair
aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME" >/dev/null 2>&1 || true
aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"

# 6) Security groups
WEB_SG_ID="$(aws ec2 create-security-group \
  --region "$REGION" \
  --group-name "${NAME_PREFIX}-web-sg" \
  --description 'web sg' \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)"

DB_SG_ID="$(aws ec2 create-security-group \
  --region "$REGION" \
  --group-name "${NAME_PREFIX}-db-sg" \
  --description 'db sg' \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)"

aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$WEB_SG_ID" --protocol tcp --port 22 --cidr "$MY_IP_CIDR"
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$WEB_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$DB_SG_ID" --protocol tcp --port 22 --source-group "$WEB_SG_ID"
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$DB_SG_ID" --protocol tcp --port 3306 --source-group "$WEB_SG_ID"

# 7) EC2 instances
WEB_USER_DATA='#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y apache2 php libapache2-mod-php php-mysql mariadb-client
systemctl enable apache2
systemctl start apache2
'

DB2_USER_DATA='#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb
'

WEB_INSTANCE_ID="$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUB1_ID" \
  --security-group-ids "$WEB_SG_ID" \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_PREFIX}-ec2-web}]" \
  --user-data "$WEB_USER_DATA" \
  --query 'Instances[0].InstanceId' --output text)"

DB1_INSTANCE_ID="$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUB2_ID" \
  --security-group-ids "$DB_SG_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_PREFIX}-ec2-db1}]" \
  --query 'Instances[0].InstanceId' --output text)"

DB2_INSTANCE_ID="$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUB3_ID" \
  --security-group-ids "$DB_SG_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_PREFIX}-ec2-db2}]" \
  --user-data "$DB2_USER_DATA" \
  --query 'Instances[0].InstanceId' --output text)"

aws ec2 wait instance-running --region "$REGION" --instance-ids "$WEB_INSTANCE_ID" "$DB1_INSTANCE_ID" "$DB2_INSTANCE_ID"

WEB_PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$WEB_INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
DB1_PRIVATE_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$DB1_INSTANCE_ID" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)"
DB2_PRIVATE_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$DB2_INSTANCE_ID" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)"

cat > infra_outputs.txt <<EOF
REGION=$REGION
VPC_ID=$VPC_ID
SUB1_ID=$SUB1_ID
SUB2_ID=$SUB2_ID
SUB3_ID=$SUB3_ID
IGW_ID=$IGW_ID
NAT_ID=$NAT_ID
WEB_SG_ID=$WEB_SG_ID
DB_SG_ID=$DB_SG_ID
KEY_NAME=$KEY_NAME
KEY_PATH=${KEY_NAME}.pem
WEB_INSTANCE_ID=$WEB_INSTANCE_ID
DB1_INSTANCE_ID=$DB1_INSTANCE_ID
DB2_INSTANCE_ID=$DB2_INSTANCE_ID
WEB_PUBLIC_IP=$WEB_PUBLIC_IP
DB1_PRIVATE_IP=$DB1_PRIVATE_IP
DB2_PRIVATE_IP=$DB2_PRIVATE_IP
EOF

echo
cat infra_outputs.txt

echo
echo "Setup done. Next:"
echo "1) Configure DB1 (scripts/02_configure_db1.sh)"
echo "2) Deploy app (scripts/03_deploy_app.sh)"
echo "3) Test http://$WEB_PUBLIC_IP/index.html and /izpis.php"
echo "4) Save screenshots into VelkovMichel/Vaja6-7/slike/..."
