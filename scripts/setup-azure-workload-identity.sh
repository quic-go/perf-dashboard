#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="quic-perf-dashboard"
APP_NAME="github-packer-builder"
REPO="quic-go/perf-dashboard"

SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
TENANT_ID="$(az account show --query tenantId --output tsv)"
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

APP_ID="$(az ad app create \
  --display-name "${APP_NAME}" \
  --query appId \
  --output tsv)"

SP_OBJECT_ID="$(az ad sp create \
  --id "${APP_ID}" \
  --query id \
  --output tsv)"

az role assignment create \
  --assignee-object-id "${SP_OBJECT_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope "${SCOPE}" \
  --output none

CREDENTIAL_FILE="$(mktemp)"
trap 'rm -f "${CREDENTIAL_FILE}"' EXIT

cat >"${CREDENTIAL_FILE}" <<EOF
{
  "name": "github-actions-master",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${REPO}:ref:refs/heads/master",
  "audiences": [
    "api://AzureADTokenExchange"
  ]
}
EOF

az ad app federated-credential create \
  --id "${APP_ID}" \
  --parameters @"${CREDENTIAL_FILE}" \
  --output none

cat >"${CREDENTIAL_FILE}" <<EOF
{
  "name": "github-actions-cloud-test",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${REPO}:environment:cloud-test",
  "audiences": [
    "api://AzureADTokenExchange"
  ]
}
EOF

az ad app federated-credential create \
  --id "${APP_ID}" \
  --parameters @"${CREDENTIAL_FILE}" \
  --output none

cat <<EOF

Set these GitHub repository variables:

AZURE_CLIENT_ID=${APP_ID}
AZURE_TENANT_ID=${TENANT_ID}
AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
AZURE_RESOURCE_GROUP=${RESOURCE_GROUP}
EOF
