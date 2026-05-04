#!/usr/bin/env bash
#
# VAJA-05 — Create an S3 bucket, configure it for static website hosting,
# and upload index.html.
#
# Usage: ./create-bucket.sh
#
set -euo pipefail

BUCKET="alma-2026-ambrozic-spletna"
REGION="eu-central-1"
INDEX_FILE="index.html"
ERROR_FILE="error.html"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ">>> [1/6] Creating bucket: $BUCKET in $REGION"
aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"

echo ">>> [2/6] Disabling public access block"
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

echo ">>> [3/6] Applying public-read bucket policy"
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
EOF
aws s3api put-bucket-policy \
    --bucket "$BUCKET" \
    --policy file:///tmp/bucket-policy.json
rm -f /tmp/bucket-policy.json

echo ">>> [4/6] Enabling static website hosting"
aws s3 website "s3://${BUCKET}/" \
    --index-document "$INDEX_FILE" \
    --error-document "$ERROR_FILE"

echo ">>> [5/6] Uploading site files"
if [[ ! -f "$INDEX_FILE" ]]; then
    echo "ERROR: $INDEX_FILE not found in $SCRIPT_DIR" >&2
    exit 1
fi
aws s3 cp "$INDEX_FILE" "s3://${BUCKET}/${INDEX_FILE}" --content-type "text/html"
if [[ -f "$ERROR_FILE" ]]; then
    aws s3 cp "$ERROR_FILE" "s3://${BUCKET}/${ERROR_FILE}" --content-type "text/html"
fi
for asset in *.jpg *.jpeg *.png *.gif *.css *.js; do
    [[ -f "$asset" ]] || continue
    aws s3 cp "$asset" "s3://${BUCKET}/${asset}"
done

echo ">>> [6/6] Done."
echo
echo "Website URL:"
echo "  http://${BUCKET}.s3-website.${REGION}.amazonaws.com"
