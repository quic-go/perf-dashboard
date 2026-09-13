import argparse
import json
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from msquic import MsQuicImplementation
from quic_go import QuicGoImplementation
from quic_implementation import SSHNode


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


def main() -> int:
    parser = argparse.ArgumentParser(description="Run one QUIC benchmark")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--identity-file", required=True, type=Path)
    common.add_argument("--server-host", required=True)
    common.add_argument("--server-ssh-port", default=22, type=_port)
    common.add_argument("--client-host", required=True)
    common.add_argument("--client-ssh-port", default=22, type=_port)
    common.add_argument(
        "--server-address",
        help="server address reachable from the client (defaults to --server-host)",
    )
    common.add_argument("--user", default="perf")
    common.add_argument(
        "--server-implementation", choices=("quic-go", "msquic"), required=True
    )
    common.add_argument(
        "--client-implementation", choices=("quic-go", "msquic"), required=True
    )
    commands = parser.add_subparsers(dest="test", required=True)
    throughput = commands.add_parser("throughput", parents=[common])
    throughput.add_argument(
        "--download-bytes", default=1_000_000_000, type=_positive_int
    )
    handshake = commands.add_parser("handshake", parents=[common])
    handshake.add_argument("--concurrency", required=True, type=_positive_int)
    handshake.add_argument("--duration-seconds", default=12, type=_positive_int)
    args = parser.parse_args()

    identity_file = args.identity_file.expanduser()
    if not identity_file.is_file():
        parser.error(f"SSH identity file does not exist: {identity_file}")

    implementations = {
        "quic-go": QuicGoImplementation,
        "msquic": MsQuicImplementation,
    }
    server_implementation = implementations[args.server_implementation]()
    client_implementation = implementations[args.client_implementation]()

    match args.test:
        case "throughput":
            parameters = {"download_bytes": args.download_bytes}
        case "handshake":
            parameters = {
                "concurrency": args.concurrency,
                "duration_seconds": args.duration_seconds,
            }
        case _:
            raise ValueError(f"unsupported benchmark: {args.test}")

    record = {
        "test": args.test,
        "client_implementation": args.client_implementation,
        "server_implementation": args.server_implementation,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "status": "failed",
        "parameters": parameters,
        "build_info": {},
    }
    with tempfile.TemporaryDirectory(prefix="quic-perf-") as temporary_directory:
        known_hosts_file = Path(temporary_directory) / "known_hosts"
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
                record["build_info"][role] = json.loads(metadata.stdout)
            try:
                server_implementation.start_server(server)
                time.sleep(3)
                address = args.server_address or args.server_host
                match args.test:
                    case "throughput":
                        result = client_implementation.run_throughput_test(
                            client, address, args.download_bytes
                        )
                        if result.bytes != args.download_bytes:
                            raise ValueError(
                                f"expected {args.download_bytes} downloaded bytes, got {result.bytes}"
                            )
                    case "handshake":
                        result = client_implementation.run_handshake_test(
                            client, address, args.concurrency, args.duration_seconds
                        )
                    case _:
                        raise ValueError(f"unsupported benchmark: {args.test}")
            finally:
                server_implementation.stop_server(server)
            record["measurements"] = {
                key: value for key, value in asdict(result).items() if value is not None
            }
            record["status"] = "success"
        finally:
            print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
        TimeoutError,
        ValueError,
    ) as error:
        print(error, file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stdout or "", file=sys.stderr, end="")
            print(error.stderr or "", file=sys.stderr, end="")
        raise SystemExit(1)
