"""Stage this fixture only; the common runner owns game/mod snapshots and launch."""
import argparse
import json
import os
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent


def prepare(cache, user, scenario, host, port, password):
    scenarios = json.loads((HERE / 'manifest.json').read_text())['scenarios']
    if user not in ('server', 'client1', 'client2') or scenario not in scenarios:
        raise ValueError('Unknown fixture actor or scenario')
    if type(port) is not int or not 1024 <= port <= 65534:
        raise ValueError('Use an unprivileged port with room for UDP port+1')
    values = [user, scenario, host, str(port), password]
    if any(not value or any(c in value for c in '\r\n\0') for value in values):
        raise ValueError('Runtime parameters must be nonempty single lines')
    helper, config = cache / 'mods/CraftPlanTest', cache / 'Lua/craft-fixture.txt'
    if helper.exists() or config.exists():
        raise ValueError('Fixture exists; use another disposable cache')
    (helper / 'common').mkdir(parents=True)
    for side in ('client', 'server'):
        target = helper / '42/media/lua' / side
        target.mkdir(parents=True)
        shutil.copy2(HERE / scenarios[scenario][side], target / 'ZZCraftFixture.lua')
    (helper / '42/mod.info').write_text('name=Isolated crafting fixture\nid=CraftPlanTest\nversionMin=42.21\n', encoding='utf-8')
    config.parent.mkdir(parents=True, exist_ok=True)
    with open(config, 'x', encoding='utf-8', opener=lambda path, flags: os.open(path, flags, 0o600)) as stream:
        stream.write('\n'.join(values) + '\n')
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cache', type=Path)
    parser.add_argument('--user', choices=('server', 'client1', 'client2'), required=True)
    parser.add_argument('--scenario', choices=('crafting', 'ui', 'alternatives'), required=True)
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--password-env', required=True, help='Environment variable name; no password in argv')
    args = parser.parse_args()
    if args.password_env not in os.environ:
        parser.error('Password environment variable is missing')
    try:
        prepare(args.cache, args.user, args.scenario, args.host, args.port, os.environ[args.password_env])
    except ValueError as error:
        parser.error(str(error))
    print('Prepared fixture only; no game, mod download, server or client was launched.')


if __name__ == '__main__':
    main()
