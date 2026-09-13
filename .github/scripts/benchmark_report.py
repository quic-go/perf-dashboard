import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser(
    description="Assemble benchmark artifacts into a report"
)
parser.add_argument("artifacts", type=Path)
parser.add_argument("--run-id", type=int, required=True)
parser.add_argument("--attempt", type=int, required=True)
parser.add_argument("--url", required=True)
parser.add_argument("--test", choices=("throughput", "handshake"), required=True)
args = parser.parse_args()

document = {
    "schema_version": 1,
    "test": args.test,
    "recorded_at": datetime.now(timezone.utc).isoformat(),
    "run": {"id": args.run_id, "attempt": args.attempt, "url": args.url},
    "nodes": {},
    "results": [
        json.loads(path.read_text())
        for path in sorted(
            args.artifacts.glob("benchmark-result-*/benchmark-result.json")
        )
    ],
}
for role in ("server", "client"):
    node = json.loads((args.artifacts / f"{role}-node" / "node.json").read_text())
    document["nodes"][role] = {
        key: node[key]
        for key in ("provider", "region", "zone", "machine_type", "image_id")
    }

print(json.dumps(document, indent=2))
