# Scripts

`setup-gcp-workload-identity.sh` creates the GCP service account and Workload Identity Federation setup used by GitHub Actions.

`setup-aws-workload-identity.sh` creates the AWS IAM role and GitHub OIDC provider used by GitHub Actions. The role gets EC2 admin permissions inside the dedicated `quic-perf-dashboard` AWS account.

The workflow authenticates without a JSON key. GitHub OIDC tokens can impersonate the Packer service account only for this repository when running on `master` or for pull requests triggered by `marten-seemann`.

Run each setup script once, then add the printed values as GitHub repository variables.
