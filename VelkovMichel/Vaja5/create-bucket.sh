#!/usr/bin/env bash
# VAJA-05 - S3 static website setup (CloudShell-ready)
# Uporaba:
#   bash create-bucket.sh
#   bash create-bucket.sh <bucket-name> <region>

set -euo pipefail

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: AWS CLI ni na voljo v trenutnem okolju." >&2
  exit 1
fi

BUCKET="${1:-alma-2026-velkov-spletna}"
REGION="${2:-eu-central-1}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo ">>> [0/6] Checking AWS identity"
aws sts get-caller-identity >/dev/null

echo ">>> [1/6] Creating bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket already exists, skipping create-bucket"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

echo ">>> [2/6] Disabling Block Public Access"
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

echo ">>> [3/6] Applying public-read bucket policy"
POLICY_FILE="$WORKDIR/bucket-policy.json"
cat > "$POLICY_FILE" <<JSON
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
JSON
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "file://${POLICY_FILE}"

echo ">>> [4/6] Enabling static website hosting"
aws s3 website "s3://${BUCKET}/" \
  --index-document index.html \
  --error-document error.html

echo ">>> [5/6] Creating and uploading website files"
cat > "$WORKDIR/index.html" <<'HTML'
<!doctype html>
<html lang="sl">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Vaja 5 - Velkov Michel</title>
  <link rel="stylesheet" href="style.css" />
</head>
<body>
  <main class="card">
    <h1>AWS S3 Static Website</h1>
    <p>Ta stran je gostovana neposredno iz S3 bucketa.</p>
    <p>Student: Velkov Michel</p>
    <img src="portret.jpg" alt="Portret" onerror="this.style.display='none'" />
  </main>
</body>
</html>
HTML

cat > "$WORKDIR/style.css" <<'CSS'
* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  font-family: Segoe UI, Arial, sans-serif;
  background: linear-gradient(130deg, #0f172a, #1d4ed8);
  color: #f8fafc;
}
.card {
  width: min(92vw, 760px);
  background: rgba(15, 23, 42, 0.75);
  border: 1px solid rgba(148, 163, 184, 0.35);
  border-radius: 14px;
  padding: 2rem;
}

img {
  margin-top: 1rem;
  max-width: 220px;
  border-radius: 10px;
  border: 1px solid rgba(148, 163, 184, 0.5);
}
CSS

cat > "$WORKDIR/error.html" <<'HTML'
<!doctype html>
<html lang="sl">
<head><meta charset="utf-8" /><title>Napaka</title></head>
<body><h1>Napaka pri nalaganju strani</h1></body>
</html>
HTML

aws s3 cp "$WORKDIR/index.html" "s3://${BUCKET}/index.html" --content-type "text/html"
aws s3 cp "$WORKDIR/style.css" "s3://${BUCKET}/style.css" --content-type "text/css"
aws s3 cp "$WORKDIR/error.html" "s3://${BUCKET}/error.html" --content-type "text/html"

echo ">>> [6/6] Done"
echo "Website URL: http://${BUCKET}.s3-website.${REGION}.amazonaws.com"
