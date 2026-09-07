import json
import sys
from pathlib import Path

document = json.loads(Path(sys.argv[1]).read_text())

print("""## Benchmark Results

| Node | Location |
| --- | --- |""")
for role, node in document["nodes"].items():
    location = node["zone"] if node["provider"] == "gcp" else node["region"]
    print(f"| {role.title()} | {node['provider']} / {location} |")

print("""
| Client | Server | Result | Upload size (MB) | Upload rate (Mbit/s) | Download size (MB) | Download rate (Mbit/s) |
| --- | --- | --- | ---: | ---: | ---: | ---: |""")
for result in document["results"]:
    client = result["client_implementation"]
    server = result["server_implementation"]
    if result["status"] != "success":
        print(f"| {client} | {server} | failed | | | | |")
        continue
    measurements = result["measurements"]
    print(
        f"| {client} | {server} | ok | "
        f"{measurements['upload_bytes'] / 1_000_000:,.0f} | "
        f"{measurements['upload_bits_per_second'] / 1_000_000:,.0f} | "
        f"{measurements['download_bytes'] / 1_000_000:,.0f} | "
        f"{measurements['download_bits_per_second'] / 1_000_000:,.0f} |"
    )
