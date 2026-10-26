"""Stage the native storage profiler in an owned disposable profile."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def prepare(toolkit_source, output):
    if not (Path(toolkit_source) / '42/mod.info').is_file():
        raise ValueError('Missing explicit Toolkit source')
    manifest = json.loads((HERE / 'manifest.json').read_text())
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    for layer in ('common', '42'):
        for name in ('AnimSets', 'actiongroups'):
            (output / layer / 'media' / name).mkdir(parents=True)
    client = output / '42/media/lua/client'
    client.mkdir(parents=True)
    fixture=manifest['fixture']
    (client / fixture).write_bytes((HERE / fixture).read_bytes())
    (output / '42/mod.info').write_text('name=Native storage profile fixture\nid=StorageProfileNative\nversionMin=42.21\n')
