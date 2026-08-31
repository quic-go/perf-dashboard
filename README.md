# quic-go Performance Dashboard

Infrastructure for running and publishing quic-go performance benchmarks.

The setup keeps runs repeatable by building AWS, GCP, and Azure runner images up front with [quic-go/perf](https://github.com/quic-go/perf) and [MsQuic](https://github.com/microsoft/msquic) installed. Each benchmark then creates short-lived server and client nodes from those images, runs every quic-go and MsQuic client/server pairing, and destroys the nodes afterward.

## Workflows

- [`.github/workflows/packer.yml`](.github/workflows/packer.yml) builds new runner images on AWS, GCP and Azure.
- [`.github/workflows/benchmark.yml`](.github/workflows/benchmark.yml) creates temporary server and client nodes and runs the implementation matrix.
- [`.github/workflows/cleanup.yml`](.github/workflows/cleanup.yml) deletes old runner images and abandoned benchmark resources.

## Testing image builds from a Pull Request

To test image builds from a pull request, open the PR normally, then go to GitHub Actions, select the `Build images` workflow, click `Run workflow`, and choose the PR branch. The AWS, GCP, and Azure build jobs then wait for approval from the `cloud-test` GitHub Environment before getting cloud credentials.

When testing changes to the workflow itself before they are merged to `master`, trigger the workflow from the CLI instead:

```bash
gh workflow run packer.yml --ref <branch-name>
```
