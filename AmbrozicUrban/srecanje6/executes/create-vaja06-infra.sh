#!/usr/bin/env bash
#
# VAJA-06 — Kreiranje AWS infrastrukture za varno spletno rešitev.
#   VPC (10.0.0.0/24) → javno podomrežje (10.0.0.0/25) + zasebno (10.0.0.128/25)
#   → IGW + route table → SG-ja (web: 22/80, db: 3306 iz sg-web) → ključni par
#   → EC2 (Debian 12, t3.micro) v javnem podomrežju → Elastic IP.
#
# Uporaba: ./create-vaja06-infra.sh
# Po koncu se stanje shrani v vaja06-state.env (uporablja teardown-vaja06.sh).
#
# Avtor: Urban Ambrožič

set -euo pipefail

PREFIX="vaja06"
REGION="eu-central-1"
VPC_CIDR="10.0.0.0/24"
PUBLIC_CIDR="10.0.0.0/25"
PRIVATE_CIDR="10.0.0.128/25"
INSTANCE_TYPE="t3.micro"
KEY_NAME="${PREFIX}-key"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

KEY_FILE="${SCRIPT_DIR}/${KEY_NAME}.pem"
STATE_FILE="${SCRIPT_DIR}/${PREFIX}-state.env"

# Kratek tag helper (Name=vaja06-...)
tag_spec() {
    local rtype="$1" name="$2"
    echo "ResourceType=${rtype},Tags=[{Key=Name,Value=${name}}]"
}

echo ">>> [1/12] Iskanje najnovejšega Debian 12 AMI-ja v ${REGION}"
AMI_ID=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners 136693071363 \
    --filters "Name=name,Values=debian-12-amd64-*" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)
echo "    AMI: $AMI_ID"

echo ">>> [2/12] Ustvarjanje VPC ${VPC_CIDR}"
VPC_ID=$(aws ec2 create-vpc \
    --region "$REGION" \
    --cidr-block "$VPC_CIDR" \
    --tag-specifications "$(tag_spec vpc ${PREFIX}-vpc)" \
    --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames
echo "    VPC: $VPC_ID"

AZ_A=$(aws ec2 describe-availability-zones --region "$REGION" \
    --query 'AvailabilityZones[0].ZoneName' --output text)
AZ_B=$(aws ec2 describe-availability-zones --region "$REGION" \
    --query 'AvailabilityZones[1].ZoneName' --output text)

echo ">>> [3/12] Ustvarjanje javnega podomrežja ${PUBLIC_CIDR} (${AZ_A})"
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
    --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --cidr-block "$PUBLIC_CIDR" \
    --availability-zone "$AZ_A" \
    --tag-specifications "$(tag_spec subnet ${PREFIX}-subnet-public)" \
    --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --region "$REGION" \
    --subnet-id "$PUBLIC_SUBNET_ID" --map-public-ip-on-launch
echo "    Public subnet: $PUBLIC_SUBNET_ID"

echo ">>> [4/12] Ustvarjanje zasebnega podomrežja ${PRIVATE_CIDR} (${AZ_B})"
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
    --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --cidr-block "$PRIVATE_CIDR" \
    --availability-zone "$AZ_B" \
    --tag-specifications "$(tag_spec subnet ${PREFIX}-subnet-private)" \
    --query 'Subnet.SubnetId' --output text)
echo "    Private subnet: $PRIVATE_SUBNET_ID"

echo ">>> [5/12] Ustvarjanje in pripenjanje Internet Gateway-ja"
IGW_ID=$(aws ec2 create-internet-gateway \
    --region "$REGION" \
    --tag-specifications "$(tag_spec internet-gateway ${PREFIX}-igw)" \
    --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region "$REGION" \
    --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
echo "    IGW: $IGW_ID"

echo ">>> [6/12] Ustvarjanje route table in default route 0.0.0.0/0 → IGW"
RTB_ID=$(aws ec2 create-route-table \
    --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag_spec route-table ${PREFIX}-rt-public)" \
    --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region "$REGION" \
    --route-table-id "$RTB_ID" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" > /dev/null
RTB_ASSOC_ID=$(aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$RTB_ID" \
    --subnet-id "$PUBLIC_SUBNET_ID" \
    --query 'AssociationId' --output text)
echo "    Route table: $RTB_ID (assoc: $RTB_ASSOC_ID)"

echo ">>> [7/12] Ustvarjanje SG ${PREFIX}-sg-web (22, 80 iz 0.0.0.0/0)"
SG_WEB_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "${PREFIX}-sg-web" \
    --description "VAJA-06 web tier: SSH + HTTP" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag_spec security-group ${PREFIX}-sg-web)" \
    --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_WEB_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_WEB_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
echo "    SG web: $SG_WEB_ID"

echo ">>> [8/12] Ustvarjanje SG ${PREFIX}-sg-db (3306 iz sg-web)"
SG_DB_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "${PREFIX}-sg-db" \
    --description "VAJA-06 db tier: MariaDB iz web SG" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag_spec security-group ${PREFIX}-sg-db)" \
    --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_DB_ID" --protocol tcp --port 3306 \
    --source-group "$SG_WEB_ID" > /dev/null
echo "    SG db:  $SG_DB_ID"

echo ">>> [9/12] Ustvarjanje ključnega para ${KEY_NAME}"
if [[ -f "$KEY_FILE" ]]; then
    echo "    Lokalni $KEY_FILE že obstaja — izbriši ali preimenuj, preden ponovno poganjaš." >&2
    exit 1
fi
aws ec2 create-key-pair --region "$REGION" \
    --key-name "$KEY_NAME" \
    --tag-specifications "$(tag_spec key-pair ${PREFIX}-key)" \
    --query 'KeyMaterial' --output text > "$KEY_FILE"
chmod 400 "$KEY_FILE"
echo "    Ključ shranjen: $KEY_FILE"

echo ">>> [10/12] Zaganjanje EC2 instance (${INSTANCE_TYPE}, Debian 12)"
INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$PUBLIC_SUBNET_ID" \
    --security-group-ids "$SG_WEB_ID" \
    --tag-specifications "$(tag_spec instance ${PREFIX}-web)" \
    --query 'Instances[0].InstanceId' --output text)
echo "    Instance: $INSTANCE_ID — čakam running ..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

echo ">>> [11/12] Dodeljevanje Elastic IP in priklop na instanco"
EIP_ALLOC_ID=$(aws ec2 allocate-address \
    --region "$REGION" \
    --domain vpc \
    --tag-specifications "$(tag_spec elastic-ip ${PREFIX}-eip)" \
    --query 'AllocationId' --output text)
EIP_ADDRESS=$(aws ec2 describe-addresses --region "$REGION" \
    --allocation-ids "$EIP_ALLOC_ID" \
    --query 'Addresses[0].PublicIp' --output text)
aws ec2 associate-address --region "$REGION" \
    --allocation-id "$EIP_ALLOC_ID" \
    --instance-id "$INSTANCE_ID" > /dev/null
echo "    EIP: $EIP_ADDRESS (alloc: $EIP_ALLOC_ID)"

echo ">>> [12/12] Shranjevanje stanja v ${STATE_FILE}"
cat > "$STATE_FILE" <<EOF
# VAJA-06 — stanje infrastrukture (generirano $(date -Iseconds))
REGION=$REGION
VPC_ID=$VPC_ID
PUBLIC_SUBNET_ID=$PUBLIC_SUBNET_ID
PRIVATE_SUBNET_ID=$PRIVATE_SUBNET_ID
IGW_ID=$IGW_ID
RTB_ID=$RTB_ID
RTB_ASSOC_ID=$RTB_ASSOC_ID
SG_WEB_ID=$SG_WEB_ID
SG_DB_ID=$SG_DB_ID
KEY_NAME=$KEY_NAME
KEY_FILE=$KEY_FILE
INSTANCE_ID=$INSTANCE_ID
EIP_ALLOC_ID=$EIP_ALLOC_ID
EIP_ADDRESS=$EIP_ADDRESS
AMI_ID=$AMI_ID
EOF

echo ""
echo "========================================="
echo "Infrastruktura pripravljena."
echo "  EC2 instance:  $INSTANCE_ID"
echo "  Elastic IP:    $EIP_ADDRESS"
echo "  SSH ukaz:      ssh -i $KEY_FILE admin@$EIP_ADDRESS"
echo "  Spletna stran: http://$EIP_ADDRESS/ (po fazi 3)"
echo "========================================="
