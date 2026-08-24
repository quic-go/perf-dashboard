#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict
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
    parser = argparse.ArgumentParser(description="Run one QUIC throughput benchmark")
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
    parser.add_argument(
        "--server-implementation", choices=("quic-go", "msquic"), required=True
    )
    parser.add_argument(
        "--client-implementation", choices=("quic-go", "msquic"), required=True
    )
    parser.add_argument("--upload-bytes", default=1_000_000_000, type=_positive_int)
    parser.add_argument("--download-bytes", default=1_000_000_000, type=_positive_int)
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
        server.wait_for_ssh()
        client.wait_for_ssh()
        server_implementation.start_server(server)
        try:
            time.sleep(3)
            result = client_implementation.run_throughput_test(
                client,
                args.server_address or args.server_host,
                args.upload_bytes,
                args.download_bytes,
            )
        finally:
            server_implementation.stop_server(server)

    print(json.dumps(asdict(result), sort_keys=True))
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
