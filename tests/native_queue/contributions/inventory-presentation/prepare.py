"""Stage the owned inventory fixture; the common native runner owns launch."""
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def prepare(toolkit_source, output):
    source = Path(toolkit_source)
    for name in ("InventoryPresentation", "InventoryCapacity", "InventoryDetails", "InventoryDetailSort",
                 "InventoryIndicators", "InventoryResearch", "InventoryPlanting", "InventoryPlantingOptions",
                 "InventoryPlantingTooltip"):
        if not (source / "42/media/lua/client/PZSurvivorToolkit" / (name + ".lua")).is_file():
            raise ValueError("Missing owned module: " + name)
    manifest = json.loads((HERE / "manifest.json").read_text())
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    for layer in ("common", "42"):
        for directory in ("AnimSets", "actiongroups"):
            (output / layer / "media" / directory).mkdir(parents=True)
    client = output / "42/media/lua/client"
    client.mkdir(parents=True)
    fixture = HERE / manifest["fixture"]
    (client / fixture.name).write_bytes(fixture.read_bytes())
    benchmark = HERE / "InventoryRenderBenchmark.lua"
    (client / benchmark.name).write_bytes(benchmark.read_bytes())
    (output / "42/mod.info").write_text("name=Inventory presentation native fixture\nid=InventoryPresentationScreens\nversionMin=42.21\n")
    (output / "fixture-manifest.json").write_text(json.dumps({"scenario": manifest["id"],
        "fixture_sha256": hashlib.sha256(fixture.read_bytes()).hexdigest()}, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolkit-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.toolkit_source, args.output)
