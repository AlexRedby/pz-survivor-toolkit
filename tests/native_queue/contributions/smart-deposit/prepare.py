"""Stage the Smart Deposit fixture; the shared runner owns isolated launch."""
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def prepare(toolkit_source, output, host=False):
    source = Path(toolkit_source) / '42/media/lua/client/PZSurvivorToolkit/SmartDeposit.lua'
    if not source.is_file():
        raise ValueError('Missing owned SmartDeposit module')
    manifest = json.loads((HERE / 'manifest.json').read_text())
    files = ({'client/ZZSmartDepositHost.lua', 'shared/QueueSmartDepositHostFixture.lua',
              'server/ZZSmartDepositHostServer.lua'} if host else {'client/' + manifest['fixture']})
    fixtures = {relative: (HERE / Path(relative).name).read_bytes() for relative in sorted(files)}
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    for layer in ('common', '42'):
        for directory in ('AnimSets', 'actiongroups'):
            (output / layer / 'media' / directory).mkdir(parents=True)
    for relative, data in fixtures.items():
        path = output / '42/media/lua' / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (output / '42/mod.info').write_text('name=Smart Deposit native fixture\nid=SmartDepositNative\nversionMin=42.21\n')
    (output / 'fixture-manifest.json').write_text(json.dumps({
        'scenario': manifest['id'],
        'kind': 'mp' if host else 'sp',
        'fixture_sha256': {name: hashlib.sha256(data).hexdigest() for name, data in fixtures.items()},
        'smart_deposit_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    }, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolkit-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.toolkit_source, args.output)
