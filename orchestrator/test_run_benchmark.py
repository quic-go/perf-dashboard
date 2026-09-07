import io
import json
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch

from msquic import _parse_result as parse_msquic_result
from quic_go import _parse_result as parse_quic_go_result
from quic_implementation import SSHNode, ThroughputResult
from run_benchmark import main


class RunBenchmarkTest(unittest.TestCase):
    def test_failure_record(self) -> None:
        args = [
            "run_benchmark.py",
            f"--identity-file={__file__}",
            "--server-host=server",
            "--client-host=client",
        ]
        with (
            patch("sys.argv", args),
            patch.object(SSHNode, "wait_for_ssh", side_effect=TimeoutError),
            redirect_stdout(io.StringIO()) as output,
            self.assertRaises(TimeoutError),
        ):
            main(Path("known_hosts"))

        record = json.loads(output.getvalue())
        self.assertEqual(record["results"], [])

    def test_continues_after_failure(self) -> None:
        args = [
            "run_benchmark.py",
            f"--identity-file={__file__}",
            "--server-host=server",
            "--client-host=client",
        ]
        results = [{"status": "failed"}] + [{"status": "success"}] * 3
        with (
            patch("sys.argv", args),
            patch.object(SSHNode, "wait_for_ssh"),
            patch.object(SSHNode, "run", return_value=Mock(stdout="{}")),
            patch("run_benchmark.run_pair", side_effect=results),
            redirect_stdout(io.StringIO()) as output,
        ):
            self.assertEqual(main(Path("known_hosts")), 1)

        self.assertEqual(json.loads(output.getvalue())["results"], results)

    def test_implementations(self) -> None:
        quic_go_output = """
2026/08/24 14:00:00 uploaded 976.56 KiB: 0.02s (320.00 mbps)
{"type":"final","uploadBytes":1000000,"uploadSeconds":0.025,"downloadBytes":1000000,"downloadSeconds":0.0125}
        """
        self.assertEqual(
            parse_quic_go_result(quic_go_output),
            ThroughputResult(1_000_000, 1_000_000, 320_000_000, 640_000_000),
        )

        msquic_output = """
Result: Upload 136274 kbps.
Result: Download 136274 kbps.
        """
        self.assertEqual(
            parse_msquic_result(msquic_output, 1_000_000, 1_000_000),
            ThroughputResult(1_000_000, 1_000_000, 136_274_000, 136_274_000),
        )


if __name__ == "__main__":
    unittest.main()
