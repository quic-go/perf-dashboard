# Scripts

`setup-gcp-workload-identity.sh` creates the GCP service account and Workload Identity Federation setup used by GitHub Actions.

`setup-aws-workload-identity.sh` creates the AWS IAM role and GitHub OIDC provider used by GitHub Actions. The role gets EC2 admin permissions inside the dedicated `quic-perf-dashboard` AWS account.

`setup-azure-workload-identity.sh` creates the Azure application, service principal, federated credentials, and role assignment used by GitHub Actions.

GitHub OIDC tokens can impersonate the GCP Packer service account, assume the AWS IAM role, and sign in as the Azure service principal only for this repository when running on `master` or when the job runs through the `cloud-test` GitHub Environment.

Run each setup script once, then add the printed values as GitHub repository variables.
