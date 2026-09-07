import json
import sys
from pathlib import Path

result_path, server_location, client_location = sys.argv[1:]

print(f"""## Benchmark Results

| Node | Location |
| --- | --- |
| Server | {server_location} |
| Client | {client_location} |

| Client | Server | Result | Upload size (MB) | Upload rate (Mbit/s) | Download size (MB) | Download rate (Mbit/s) |
| --- | --- | --- | ---: | ---: | ---: | ---: |""")

for result in json.loads(Path(result_path).read_text())["results"]:
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
