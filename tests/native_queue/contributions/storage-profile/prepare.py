"""Stage the native storage profiler in an owned disposable profile."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def prepare(toolkit_source, output, case='walk', cases=None):
    if not (Path(toolkit_source) / '42/mod.info').is_file():
        raise ValueError('Missing explicit Toolkit source')
    manifest = json.loads((HERE / 'manifest.json').read_text())
    if cases is not None and cases != ['inventory-work', 'inventory-freshness']:
        raise ValueError('Storage shared session requires fresh inventory-work then inventory-freshness')
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    for layer in ('common', '42'):
        for name in ('AnimSets', 'actiongroups'):
            (output / layer / 'media' / name).mkdir(parents=True)
    client = output / '42/media/lua/client'
    client.mkdir(parents=True)
    if cases is not None:
        shared = output / '42/media/lua/shared'
        shared.mkdir(parents=True)
        for name in ('StorageProfileSession.lua', 'ZZInventoryWorkProfile.lua', 'ZZInventoryFreshness.lua', 'ReceiptLookupNative.lua'):
            body = (HERE / name).read_bytes()
            # Native loads shared scripts eagerly. Case factories remain dormant
            # until the coordinator owns their epoch; no fixture code is replaced.
            if name in ('ZZInventoryWorkProfile.lua', 'ZZInventoryFreshness.lua'):
                body = b'return function()\n' + body + b'\nend\n'
            (shared / name).write_bytes(body)
        (shared / 'QueueFixtureSession.lua').write_bytes((HERE.parents[1] / 'support/QueueFixtureSession.lua').read_bytes())
        (client / 'ZZStorageSession.lua').write_bytes((HERE / 'ZZStorageSession.lua').read_bytes())
    elif case not in manifest['cases']:
        raise ValueError('Unsupported storage profile case')
    else:
        fixture = {'walk': manifest['fixture'], 'inventory-work': 'ZZInventoryWorkProfile.lua',
                   'inventory-freshness': 'ZZInventoryFreshness.lua',
                   'inventory-food-age': 'ZZFoodAgeNative.lua'}[case]
        (client / fixture).write_bytes((HERE / fixture).read_bytes())
        if case == 'inventory-food-age':
            for side, name in (('shared', 'QueueFoodAgeFixture.lua'), ('server', 'ZZFoodAgeServer.lua')):
                destination = output / '42/media/lua' / side
                destination.mkdir(parents=True, exist_ok=True)
                (destination / name).write_bytes((HERE / name).read_bytes())
        if case not in ('inventory-freshness', 'inventory-food-age'):
            helper='StorageFairnessNative.lua' if case == 'walk' else 'ReceiptLookupNative.lua'
            (client / helper).write_bytes((HERE / helper).read_bytes())
    (output / '42/mod.info').write_text('name=Native storage profile fixture\nid=StorageProfileNative\nversionMin=42.21\n')
