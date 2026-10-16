"""Prepare the item-tags helper mod; launching the game belongs to the common runner."""

import argparse
import hashlib
import json
from pathlib import Path
import re


HERE = Path(__file__).resolve().parent
VISUALS = Path("42/media/lua/client/PZSurvivorToolkit/TagVisuals.lua")
FIXTURE = "ZZQuartermasterScreens.lua"
MARKER = " -- VISUAL_TEXTURE_GATE"


def prepare(toolkit_source: Path, output: Path) -> int:
    visuals = (toolkit_source / VISUALS).read_text(encoding="utf-8")
    source = (HERE / FIXTURE).read_text(encoding="utf-8")
    textures = sorted(set(re.findall(r'"((?:Item_|media/ui/)[^"]+)"', visuals)))
    if not textures or source.count(MARKER) != 1:
        raise ValueError("Expected visual texture references and one fixture gate marker")
    gate = "\n".join(
        f" assert(getTexture({json.dumps(name)}),{json.dumps('Missing visual texture ' + name)})"
        for name in textures
    )
    gate += f"\n print('[QM_SCREEN] VISUAL {len(textures)} textures loaded')"
    fixture = source.replace(MARKER, gate)
    output.mkdir(parents=True, exist_ok=False)
    for version in ("common", "42"):
        for directory in ("AnimSets", "actiongroups"):
            (output / version / "media" / directory).mkdir(parents=True)
    client = output / "42/media/lua/client"
    client.mkdir(parents=True)
    (client / FIXTURE).write_text(fixture, encoding="utf-8")
    (output / "42/mod.info").write_text(
        "name=Item tags native fixture\nid=QuartermasterScreens\nversionMin=42.21\n", encoding="utf-8"
    )
    (output / "fixture-manifest.json").write_text(json.dumps({
        "scenario": "item-tags",
        "fixture_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "visuals_sha256": hashlib.sha256(visuals.encode()).hexdigest(),
        "textures": textures,
    }, indent=2) + "\n", encoding="utf-8")
    return len(textures)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolkit-source", type=Path, required=True,
                        help="Toolkit mod directory containing 42/media/lua")
    parser.add_argument("--output", type=Path, required=True,
                        help="New helper mod directory; must not exist")
    args = parser.parse_args()
    count = prepare(args.toolkit_source, args.output)
    print(f"Prepared QuartermasterScreens with {count} texture assertions")
