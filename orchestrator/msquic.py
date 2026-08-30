import re

from quic_implementation import QuicImplementation, SSHNode, ThroughputResult


def _parse_rate(output: str, direction: str) -> int:
    match = re.search(
        rf"Result: {direction} ([0-9.]+) ([kmg]?bps)\.", output, re.IGNORECASE
    )
    if not match:
        raise ValueError(f"could not parse MsQuic benchmark output:\n{output}")
    scales = {"bps": 1, "kbps": 1_000, "mbps": 1_000_000, "gbps": 1_000_000_000}
    return round(float(match.group(1)) * scales[match.group(2).lower()])


def _parse_result(
    output: str, upload_bytes: int, download_bytes: int
) -> ThroughputResult:
    return ThroughputResult(
        upload_bytes=upload_bytes,
        download_bytes=download_bytes,
        upload_bits_per_second=_parse_rate(output, "Upload"),
        download_bits_per_second=_parse_rate(output, "Download"),
    )


class MsQuicImplementation(QuicImplementation):
    server_command = (
        "/opt/msquic/build/bin/Release/secnetperf",
        "-exec:maxtput",
        "-bind:0.0.0.0",
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
                "/opt/msquic/build/bin/Release/secnetperf",
                f"-target:{server_address}",
                "-port:4433",
                "-exec:maxtput",
                f"-up:{upload_bytes}",
                f"-down:{download_bytes}",
                "-ptput:1",
            ),
            capture_output=True,
            timeout=15 * 60,
        )
        return _parse_result(
            completed.stdout + completed.stderr, upload_bytes, download_bytes
        )
