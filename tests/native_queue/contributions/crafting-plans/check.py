"""No-game intake validation; stage registration is not a native pass."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def main():
    manifest = json.loads((HERE / 'manifest.json').read_text())
    assert manifest['status'] == 'intake-only' and manifest['native_kinds'] == ['mp']
    expected = {'crafting': 20, 'ui': 28, 'alternatives': 23}
    assert {k: v['historical_checks_per_client'] for k, v in manifest['scenarios'].items()} == expected
    spec = importlib.util.spec_from_file_location('craft_prepare', HERE / 'prepare.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        for scenario in expected:
            sources = []
            for user in ('server', 'client1', 'client2'):
                cache = root / scenario / user
                config = module.prepare(cache, user, scenario, 'configured-host', 12345, 'ephemeral-check-value')
                assert config.read_text().splitlines()[:4] == [user, scenario, 'configured-host', '12345']
                assert config.stat().st_mode & 0o077 == 0
                helper = cache / 'mods/CraftPlanTest'
                sources.append({str(p.relative_to(helper)): p.read_bytes() for p in helper.rglob('*') if p.is_file()})
                for side in ('client', 'server'):
                    assert sources[-1]['42/media/lua/' + side + '/ZZCraftFixture.lua'] == (HERE / manifest['scenarios'][scenario][side]).read_bytes()
                try:
                    module.prepare(cache, user, scenario, 'configured-host', 12345, 'ephemeral-check-value')
                except ValueError:
                    pass
                else:
                    raise AssertionError('Prepared cache overwritten')
            assert sources[0] == sources[1] == sources[2], 'Per-role mod bytes would break Lua checksums'
        for user, scenario, host, port, password in [
            ('unknown','ui','host',12345,'value'), ('client1','unknown','host',12345,'value'),
            ('client1','ui','host\nextra',12345,'value'), ('client1','ui','host',65535,'value'),
            ('client1','ui','host',12345,''),
        ]:
            try:
                module.prepare(root / 'invalid', user, scenario, host, port, password)
            except ValueError:
                pass
            else:
                raise AssertionError('Invalid fixture configuration accepted')
        assert not (root / 'invalid').exists()
    lua = shutil.which('luajit') or shutil.which('lua5.1')
    if not lua:
        raise SystemExit('LuaJIT or Lua 5.1 required for syntax/registration checks')
    subprocess.run([lua, str(HERE / 'check.lua'), str(HERE)], check=True)
    print('PASS fixture staging, identical checksummed mod bytes, private configuration and collision/parameter guards')
    print('NOT RUN: PZ, SP/MP, rendered UI, native crafting or network')


if __name__ == '__main__':
    main()
