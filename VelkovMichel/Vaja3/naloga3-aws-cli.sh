#!/bin/bash
set -e

REGION="eu-north-1"
AMI_ID="ami-01ef747f983799d6f"
VPC_ID="vpc-0f8fc5a42a06e4d02"
SUBNET_ID="subnet-0092ca7d18a298361"
KEY_NAME="naloga 3"
SG_NAME="naloga3-apache-$(date +%s)"
INSTANCE_NAME="naloga3-apache-cli"
MY_IP="$(curl -s https://checkip.amazonaws.com | tr -d '\r\n')/32"

cat > setup-apache.sh <<'EOF'
#!/bin/bash
set -e
apt update -y
apt upgrade -y
apt install apache2 -y
systemctl enable --now apache2
echo "<h1>Apache na EC2 deluje</h1>" > /var/www/html/index.html
EOF

chmod +x setup-apache.sh

SG_ID=$(aws ec2 create-security-group \
  --region "$REGION" \
  --group-name "$SG_NAME" \
  --description "SSH + HTTP for naloga 3" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr "$MY_IP"

aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

INSTANCE_ID=$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --associate-public-ip-address \
  --count 1 \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --user-data file://setup-apache.sh \
  --query 'Instances[0].InstanceId' \
  --output text)

aws ec2 wait instance-running \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "INSTANCE_ID=$INSTANCE_ID"
echo "SG_ID=$SG_ID"
echo "PUBLIC_IP=$PUBLIC_IP"
curl "http://$PUBLIC_IP"
