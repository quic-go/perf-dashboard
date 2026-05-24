# quic-go Performance Dashboard

Infrastructure for running and publishing quic-go performance benchmarks. Builds runner images for AWS, GCP, and Azure that come preloaded with the quic-go and MsQuic perf binaries.

## Testing image builds from a Pull Request

To test image builds from a pull request, open the PR normally, then go to GitHub Actions, select the `Build images` workflow, click `Run workflow`, choose the PR branch, and set `debug` to `true`. The AWS, GCP, and Azure build jobs then wait for approval from the `cloud-test` GitHub Environment before getting cloud credentials.

When testing changes to the workflow itself before they are merged to `master`, trigger the workflow from the CLI instead:

```bash
gh workflow run packer.yml --ref <branch-name> -f debug=true
```
