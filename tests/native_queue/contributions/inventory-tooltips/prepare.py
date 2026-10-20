"""Stage the tooltip helper; the shared native runner owns isolated launch."""
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULES = ('InventoryTooltip', 'InventoryMediaTooltip', 'InventoryPlantingTooltip', 'InventoryClothingTooltip')


def prepare(toolkit_source, output):
    source = Path(toolkit_source) / '42/media/lua/client/PZSurvivorToolkit'
    modules = {name: source / (name + '.lua') for name in MODULES}
    for name, path in modules.items():
        if not path.is_file():
            raise ValueError('Missing owned module: ' + name)
    manifest = json.loads((HERE / 'manifest.json').read_text())
    fixture = HERE / manifest['fixture']
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    for layer in ('common', '42'):
        for directory in ('AnimSets', 'actiongroups'):
            (output / layer / 'media' / directory).mkdir(parents=True)
    client = output / '42/media/lua/client'
    client.mkdir(parents=True)
    (client / fixture.name).write_bytes(fixture.read_bytes())
    (output / '42/mod.info').write_text(
        'name=Inventory tooltip native fixture\nid=InventoryTooltipNative\nversionMin=42.21\n')
    (output / 'fixture-manifest.json').write_text(json.dumps({
        'scenario': manifest['id'],
        'fixture_sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(),
        'source_sha256': {name: hashlib.sha256(path.read_bytes()).hexdigest()
                          for name, path in modules.items()},
    }, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolkit-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.toolkit_source, args.output)
