import io
import json
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from msquic import _parse_result as parse_msquic_result
from quic_go import _parse_result as parse_quic_go_result
from quic_implementation import HandshakeResult, SSHNode, ThroughputResult
from run_benchmark import main


class RunBenchmarkTest(unittest.TestCase):
    def test_downloads(self) -> None:
        quic_go_output = (
            "progress log\n"
            '{"type":"final","downloadBytes":2000000,"timeSeconds":0.025,"downloadSeconds":0.02}\n'
        )
        self.assertEqual(
            parse_quic_go_result(quic_go_output, "throughput"),
            ThroughputResult(2_000_000, 0.025, 640_000_000),
        )
        self.assertEqual(
            parse_msquic_result(
                "Started!\nResult: Download 2000000 bytes @ 640000 kbps (25.000 ms).\n",
                "throughput",
            ),
            ThroughputResult(2_000_000, 0.025, 640_000_000),
        )

    def test_failure_record(self) -> None:
        args = [
            "run_benchmark.py",
            "throughput",
            f"--identity-file={__file__}",
            "--server-host=server",
            "--client-host=client",
            "--server-implementation=quic-go",
            "--client-implementation=msquic",
        ]
        with (
            patch("sys.argv", args),
            patch.object(SSHNode, "wait_for_ssh", side_effect=TimeoutError),
            redirect_stdout(io.StringIO()) as output,
            self.assertRaises(TimeoutError),
        ):
            main()

        record = json.loads(output.getvalue())
        self.assertEqual(record["status"], "failed")
        self.assertNotIn("measurements", record)
        self.assertEqual(record["parameters"], {"download_bytes": 1_000_000_000})

    def test_handshakes(self) -> None:
        quic_go_output = (
            'log\n{"type":"intermediary"}\n'
            '{"type":"final","timeSeconds":2,"handshakes":200,"failedHandshakes":1,"incompleteHandshakes":3,"handshakesPerSecond":100}\n'
        )
        self.assertEqual(
            parse_quic_go_result(quic_go_output, "handshake"),
            HandshakeResult(100, 200, 1, 3),
        )
        self.assertEqual(
            parse_msquic_result("Started!\nResult: 100 HPS\n", "handshake"),
            HandshakeResult(100),
        )


if __name__ == "__main__":
    unittest.main()
