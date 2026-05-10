#!/usr/bin/env bash
set -euo pipefail

AWS_ACCOUNT_ID="876225478118"
ROLE_NAME="github-packer-builder"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com

aws iam create-role \
  --role-name "${ROLE_NAME}" \
  --assume-role-policy-document aws-github-actions-trust-policy.json

aws iam attach-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

cat <<EOF

Set this GitHub repository variable:

AWS_ROLE_TO_ASSUME=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}
EOF
