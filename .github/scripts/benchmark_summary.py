import json
import sys
from pathlib import Path

document = json.loads(Path(sys.argv[1]).read_text())

handshake = document.get("test", "throughput") == "handshake"
print(f"## {'Handshake' if handshake else 'Download'} Benchmark Results")
print("""

| Node | Location |
| --- | --- |""")
for role, node in document["nodes"].items():
    location = node["zone"] if node["provider"] == "gcp" else node["region"]
    print(f"| {role.title()} | {node['provider']} / {location} |")

if handshake:
    print("""
| Client | Server | Result | Concurrency | Duration (s) | Handshakes/s |
| --- | --- | --- | ---: | ---: | ---: |""")
else:
    print("""
| Client | Server | Result | Size (MB) | Duration (s) | Rate (Mbit/s) |
| --- | --- | --- | ---: | ---: | ---: |""")
for result in document["results"]:
    client = result["client_implementation"]
    server = result["server_implementation"]
    if result["status"] != "success":
        print(f"| {client} | {server} | failed | | | |")
        continue
    measurements = result["measurements"]
    if handshake:
        parameters = result["parameters"]
        print(
            f"| {client} | {server} | ok | {parameters['concurrency']} | "
            f"{parameters['duration_seconds']} | "
            f"{measurements['handshakes_per_second']:,.1f} |"
        )
    else:
        print(
            f"| {client} | {server} | ok | "
            f"{measurements['bytes'] / 1_000_000:,.0f} | "
            f"{measurements['duration_seconds']:,.3f} | "
            f"{measurements['bits_per_second'] / 1_000_000:,.0f} |"
        )
