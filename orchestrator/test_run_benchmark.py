import unittest

from msquic import _parse_result as parse_msquic_result
from quic_go import _parse_result as parse_quic_go_result
from quic_implementation import ThroughputResult


class ParseThroughputResultTest(unittest.TestCase):
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
