import re

from quic_implementation import (
    HandshakeResult,
    QuicImplementation,
    SSHNode,
    ThroughputResult,
)


def _parse_result(output: str, test: str) -> ThroughputResult | HandshakeResult:
    if test == "handshake":
        match = re.search(r"Result: (\d+) HPS\b", output)
        if not match or int(match.group(1)) == 0:
            raise ValueError(f"could not parse MsQuic handshake measurement:\n{output}")
        return HandshakeResult(handshakes_per_second=int(match.group(1)))
    match = re.search(
        r"Result: Download (\d+) bytes @ \d+ kbps \((\d+\.\d+) ms\)\.", output
    )
    if not match:
        raise ValueError(f"could not parse MsQuic benchmark output:\n{output}")
    num_bytes = int(match.group(1))
    duration = float(match.group(2)) / 1_000
    if num_bytes <= 0 or duration <= 0:
        raise ValueError(f"invalid MsQuic download measurement:\n{output}")
    return ThroughputResult(
        bytes=num_bytes,
        duration_seconds=duration,
        bits_per_second=round(num_bytes * 8 / duration),
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
        download_bytes: int,
    ) -> ThroughputResult:
        completed = client.run(
            (
                "/opt/msquic/build/bin/Release/secnetperf",
                f"-target:{server_address}",
                "-port:4433",
                "-exec:maxtput",
                "-up:0",
                f"-down:{download_bytes}",
                "-pctput:1",
            ),
            capture_output=True,
            timeout=15 * 60,
        )
        return _parse_result(completed.stdout + completed.stderr, "throughput")

    def run_handshake_test(
        self,
        client: SSHNode,
        server_address: str,
        concurrency: int,
        duration_seconds: int,
    ) -> HandshakeResult:
        completed = client.run(
            (
                "/opt/msquic/build/bin/Release/secnetperf",
                f"-target:{server_address}",
                "-port:4433",
                "-scenario:hps",
                f"-conns:{concurrency}",
                f"-runtime:{duration_seconds}s",
            ),
            capture_output=True,
            timeout=duration_seconds + 30,
        )
        return _parse_result(completed.stdout + completed.stderr, "handshake")
