import json

from quic_implementation import QuicImplementation, SSHNode, ThroughputResult


def _parse_result(output: str) -> ThroughputResult:
    for line in output.splitlines():
        try:
            result = json.loads(line)
            if isinstance(result, dict) and result.get("type") == "final":
                return ThroughputResult(
                    upload_bytes=result["uploadBytes"],
                    download_bytes=result["downloadBytes"],
                    upload_bits_per_second=round(
                        result["uploadBytes"] * 8 / result["uploadSeconds"]
                    ),
                    download_bits_per_second=round(
                        result["downloadBytes"] * 8 / result["downloadSeconds"]
                    ),
                )
        except (json.JSONDecodeError, KeyError, TypeError, ZeroDivisionError):
            continue
    raise ValueError(f"could not parse quic-go benchmark output:\n{output}")


class QuicGoImplementation(QuicImplementation):
    server_command = (
        "/opt/quic-go/perf/quic-go-perf",
        "--run-server",
        "--server-address=0.0.0.0:4433",
    )

    def run_throughput_test(
        self,
        client: SSHNode,
        server_address: str,
        upload_bytes: int,
        download_bytes: int,
    ) -> ThroughputResult:
        completed = client.run(
            (
                "/opt/quic-go/perf/quic-go-perf",
                f"--server-address={server_address}:4433",
                f"--upload-bytes={upload_bytes}",
                f"--download-bytes={download_bytes}",
            ),
            capture_output=True,
            timeout=15 * 60,
        )
        return _parse_result(completed.stdout + completed.stderr)
