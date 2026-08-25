import shlex
import subprocess
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ThroughputResult:
    upload_bytes: int
    download_bytes: int
    upload_bits_per_second: int
    download_bits_per_second: int


@dataclass(frozen=True)
class SSHNode:
    host: str
    port: int
    user: str
    identity_file: Path
    known_hosts_file: Path

    def run(
        self,
        command: str | tuple[str, ...],
        *,
        check: bool = True,
        capture_output: bool = False,
        timeout: float | None = None,
    ) -> subprocess.CompletedProcess[str]:
        if not isinstance(command, str):
            command = shlex.join(command)
        args = ["ssh", "-i", str(self.identity_file), "-p", str(self.port)]
        args += ["-oBatchMode=yes", "-oConnectTimeout=5"]
        args += ["-oStrictHostKeyChecking=accept-new"]
        args += [f"-oUserKnownHostsFile={self.known_hosts_file}"]
        args += [f"{self.user}@{self.host}", command]
        return subprocess.run(
            args,
            check=check,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
        )

    def wait_for_ssh(self, timeout: float = 60) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                attempt = self.run("true", check=False, capture_output=True, timeout=6)
                if attempt.returncode == 0:
                    return
            except subprocess.TimeoutExpired:
                pass
            time.sleep(1)
        raise TimeoutError(f"SSH did not become ready at {self.host}:{self.port}")


class QuicImplementation(ABC):
    server_command: tuple[str, ...]

    @abstractmethod
    def run_throughput_test(
        self,
        client: SSHNode,
        server_address: str,
        upload_bytes: int,
        download_bytes: int,
    ) -> ThroughputResult:
        pass

    def start_server(self, server: SSHNode) -> None:
        command = shlex.join(self.server_command)
        server.run(
            f"nohup {command} >/tmp/benchmark-server.log 2>&1 & "
            "echo $! >/tmp/benchmark-server.pid",
            timeout=10,
        )

    def stop_server(self, server: SSHNode) -> None:
        server.run(
            "if [ -f /tmp/benchmark-server.pid ]; then "
            'kill "$(cat /tmp/benchmark-server.pid)" 2>/dev/null || true; '
            "rm -f /tmp/benchmark-server.pid; fi",
            capture_output=True,
            timeout=10,
        )
