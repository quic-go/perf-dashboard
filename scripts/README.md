# Scripts

`setup-gcp-workload-identity.sh` creates the GCP service account and Workload Identity Federation setup used by GitHub Actions.

The workflow authenticates without a JSON key. GitHub OIDC tokens can impersonate the Packer service account only for this repository when running on `master`, for pull requests targeting `master`, or when triggered by `marten-seemann`.

Run the script once, then add the printed values as GitHub repository variables.
