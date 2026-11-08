#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="quic-perf-dashboard"
PROJECT_NUMBER="956155714051"
REPO="quic-go/perf-dashboard"
SERVICE_ACCOUNT="github-packer-builder@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create github-packer-builder \
  --project="${PROJECT_ID}" \
  --display-name="GitHub Packer Builder"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition=None

gcloud iam workload-identity-pools create github-actions \
  --project="${PROJECT_ID}" \
  --location=global \
  --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers create-oidc perf-dashboard \
  --project="${PROJECT_ID}" \
  --location=global \
  --workload-identity-pool=github-actions \
  --display-name="${REPO}" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == '${REPO}' && (assertion.ref == 'refs/heads/master' || assertion.sub == 'repo:${REPO}:environment:cloud-test')"

gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/attribute.repository/${REPO}"

# The benchmark nodes use the default network, which GCP creates with a
# 1,460-byte MTU. Raise it to the 1,500 bytes of AWS and Azure, so that
# MsQuic's 1,500-byte path MTU probes aren't lost.
gcloud compute networks update default \
  --project="${PROJECT_ID}" \
  --mtu=1500

cat <<EOF

Set these GitHub repository variables:

GCP_PROJECT_ID=${PROJECT_ID}
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/providers/perf-dashboard
GCP_PACKER_SERVICE_ACCOUNT=${SERVICE_ACCOUNT}
EOF
