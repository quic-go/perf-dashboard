import json
import math

from quic_implementation import (
    HandshakeResult,
    QuicImplementation,
    SSHNode,
    ThroughputResult,
)


def _parse_result(output: str, test: str) -> ThroughputResult | HandshakeResult:
    for line in output.splitlines():
        try:
            result = json.loads(line)
            if isinstance(result, dict) and result.get("type") == "final":
                if test == "handshake":
                    rate = result["handshakesPerSecond"]
                    if not math.isfinite(rate) or rate <= 0:
                        continue
                    return HandshakeResult(
                        handshakes_per_second=rate,
                        handshakes=result["handshakes"],
                        failed_handshakes=result["failedHandshakes"],
                        incomplete_handshakes=result["incompleteHandshakes"],
                    )
                num_bytes = result["downloadBytes"]
                duration = result["timeSeconds"]
                if num_bytes <= 0 or not math.isfinite(duration) or duration <= 0:
                    continue
                return ThroughputResult(
                    bytes=num_bytes,
                    duration_seconds=duration,
                    bits_per_second=round(num_bytes * 8 / duration),
                )
        except (json.JSONDecodeError, KeyError, TypeError, ZeroDivisionError):
            continue
    raise ValueError(f"could not parse quic-go benchmark output:\n{output}")


class QuicGoImplementation(QuicImplementation):
    server_command = (
        "/opt/quic-go/perf/quic-go-perf",
        "server",
        "--address=0.0.0.0:4433",
    )

    def run_throughput_test(
        self,
        client: SSHNode,
        server_address: str,
        download_bytes: int,
    ) -> ThroughputResult:
        completed = client.run(
            (
                "/opt/quic-go/perf/quic-go-perf",
                "throughput",
                f"--address={server_address}:4433",
                f"--download-bytes={download_bytes}",
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
                "/opt/quic-go/perf/quic-go-perf",
                "handshake",
                f"--address={server_address}:4433",
                f"--concurrency={concurrency}",
                f"--duration={duration_seconds}s",
            ),
            capture_output=True,
            timeout=duration_seconds + 30,
        )
        return _parse_result(completed.stdout + completed.stderr, "handshake")
