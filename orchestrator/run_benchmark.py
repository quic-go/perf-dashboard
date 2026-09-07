import argparse
import json
import logging
import tempfile
import time
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from msquic import MsQuicImplementation
from quic_go import QuicGoImplementation
from quic_implementation import QuicImplementation, SSHNode

logger = logging.getLogger(__name__)


def _positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def _port(value: str) -> int:
    number = int(value)
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError("must be between 1 and 65535")
    return number


def main(known_hosts_file: Path) -> int:
    parser = argparse.ArgumentParser(
        description="Run all QUIC throughput benchmark pairings"
    )
    parser.add_argument("--identity-file", required=True, type=Path)
    parser.add_argument("--server-host", required=True)
    parser.add_argument("--server-ssh-port", default=22, type=_port)
    parser.add_argument("--client-host", required=True)
    parser.add_argument("--client-ssh-port", default=22, type=_port)
    parser.add_argument(
        "--server-address",
        help="server address reachable from the client (defaults to --server-host)",
    )
    parser.add_argument("--user", default="perf")
    parser.add_argument("--upload-bytes", default=1_000_000_000, type=_positive_int)
    parser.add_argument("--download-bytes", default=1_000_000_000, type=_positive_int)
    args = parser.parse_args()

    identity_file = args.identity_file.expanduser()
    if not identity_file.is_file():
        parser.error(f"SSH identity file does not exist: {identity_file}")

    implementations = {
        "quic-go": QuicGoImplementation(),
        "msquic": MsQuicImplementation(),
    }
    document = {"build_info": {}, "results": []}
    server = SSHNode(
        args.server_host,
        args.server_ssh_port,
        args.user,
        identity_file,
        known_hosts_file,
    )
    client = SSHNode(
        args.client_host,
        args.client_ssh_port,
        args.user,
        identity_file,
        known_hosts_file,
    )
    try:
        server.wait_for_ssh()
        client.wait_for_ssh()
        for role, node in (("server", server), ("client", client)):
            metadata = node.run(
                ("cat", "/home/perf/build-info.json"),
                capture_output=True,
                timeout=10,
            )
            document["build_info"][role] = json.loads(metadata.stdout)

        for server_name, server_implementation in implementations.items():
            for client_name, client_implementation in implementations.items():
                document["results"].append(
                    run_pair(
                        server,
                        client,
                        server_name,
                        client_name,
                        server_implementation,
                        client_implementation,
                        args.server_address or args.server_host,
                        args.upload_bytes,
                        args.download_bytes,
                    )
                )
    finally:
        print(json.dumps(document, sort_keys=True))
    return int(any(result["status"] != "success" for result in document["results"]))


def run_pair(
    server: SSHNode,
    client: SSHNode,
    server_name: str,
    client_name: str,
    server_implementation: QuicImplementation,
    client_implementation: QuicImplementation,
    server_address: str,
    upload_bytes: int,
    download_bytes: int,
) -> dict:
    record = {
        "test": "throughput",
        "client_implementation": client_name,
        "server_implementation": server_name,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "status": "failed",
        "parameters": {
            "upload_bytes": upload_bytes,
            "download_bytes": download_bytes,
        },
    }
    try:
        try:
            server_implementation.start_server(server)
            time.sleep(3)
            result = client_implementation.run_throughput_test(
                client, server_address, upload_bytes, download_bytes
            )
        finally:
            server_implementation.stop_server(server)
        record["measurements"] = asdict(result)
        record["status"] = "success"
    except Exception:
        logger.exception("%s client → %s server failed", client_name, server_name)
    return record


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="quic-perf-") as temporary_directory:
        raise SystemExit(main(Path(temporary_directory) / "known_hosts"))
