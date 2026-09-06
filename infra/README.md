# Benchmark Infrastructure

This directory contains one Terraform root per cloud provider; the benchmark workflow selects the root using `cloud_provider`.

- `infra/aws`: launches an EC2 node from the latest `quic-perf-runner` AMI in `aws_source_region`, copying it to `location` when needed.
- `infra/gcp`: launches a Compute Engine node from the `quic-perf-runner` image family.
- `infra/azure`: launches an Azure VM from the latest retained managed image, creating a temporary Compute Gallery copy when needed.

Common variables:

- `name`: unique name for the node and temporary resources.
- `location`: AWS region, GCP zone, or Azure region.

Provider variables:

- `aws_source_region`: AWS source AMI region, defaults to `us-west-2`.
- `gcp_project_id`: GCP project ID.
- `azure_subscription_id`: Azure subscription ID.
- `azure_resource_group`: Azure resource group containing retained Packer images.
- `ssh_public_key`: Azure admin SSH public key; AWS and GCP use SSH keys baked into the image.

Outputs:

- `node`: provider, region, zone, machine type, image ID, and public IP.
