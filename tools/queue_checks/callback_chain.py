"""Exact selected dashboard call-chain spans, only in a disposable owned snapshot."""
import hashlib
import json
from pathlib import Path

SOURCES = (('mods/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDoorDashboard.lua',
  'd4be1387c7e55abc5a2d31fc5518a2a06fe31dace4830087cb054f7549178e2c',
  '        prerender(self, ...)',
  '        PZDrivingCallbackCall(prerender, self, ...)'),
 ('mods/NepHighBeams/42/media/lua/client/NepHB_highbeams.lua',
  'bbae57210385519c10f3769b27cf2db0a5d18b69002adbaf1750c6e753b89cdc',
  '\tNepHBoriginal_dahboardPrerender(self)',
  '\tPZDrivingCallbackCall(NepHBoriginal_dahboardPrerender, self)'),
 ('mods/RealisticDash/42/media/lua/client/Vehicles/ISUI/Z_PatchVehicleDashboard.lua',
  'd2b74975e775890d2682d42c8eaae2b89e3be460db975a9194320ec77bc98492',
  '    _oldPrerender(self)',
  '    PZDrivingCallbackCall(_oldPrerender, self)'),
 ('mods/RealisticDash/42/media/lua/client/Vehicles/ISUI/Z_PatchVehicleDashboard_AC.lua',
  '681ac681960de9ca51a3dff4c47032121f1d21d441519fa15a2f84e0bb0d32c9',
  'oldPrerender(self)',
  'PZDrivingCallbackCall(oldPrerender, self)'),
 ('mods/RealisticDash/42/media/lua/client/Vehicles/ISUI/Z_PatchVehicleDashboard_RadioRouter.lua',
  '077aa346c9de438ec884bef725e9d0e469db16584860c3f6b1c428a61b3e9540',
  '_basePrerender(self)',
  'PZDrivingCallbackCall(_basePrerender, self)'),
 ('mods/RealisticDash/42/media/lua/client/Vehicles/ISUI/ZZZ_YourDashSport.lua',
  '6356d6fedf9c93d49a8db6f7ad0d65568d205e9da9623ab5a852a947091cf657',
  'oldPrerender(self)',
  'PZDrivingCallbackCall(oldPrerender, self)'))


def _owned(cache, relative):
    path = cache / relative
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(cache.resolve()):
        raise ValueError('Callback chain requires an owned regular snapshot: ' + relative)
    return path


def stage(cache):
    cache = Path(cache)
    pending = []
    # Review all exact sources before changing any of the disposable copies.
    for relative, expected, before, after in SOURCES:
        path = _owned(cache, relative)
        data = path.read_bytes()
        temporary = path.with_name(path.name + '.callback-chain.tmp')
        if hashlib.sha256(data).hexdigest() != expected or data.count(before.encode()) != 1:
            raise ValueError('Callback chain selected source changed: ' + relative)
        if temporary.exists() or temporary.is_symlink():
            raise ValueError('Callback chain temporary file exists')
        changed = data.replace(before.encode(), after.encode())
        pending.append((path, temporary, changed, dict(source=relative, before_sha256=expected,
            after_sha256=hashlib.sha256(changed).hexdigest())))
    for path, temporary, data, record in pending:
        temporary.write_bytes(data)
        temporary.replace(path)  # Never write through copied-source hard links.
    receipt = dict(format=1, sources=[entry[3] for entry in pending])
    (cache / 'callback-chain-staging.json').write_text(json.dumps(receipt, sort_keys=True) + '\n', encoding='utf-8')
    return receipt


def verify(cache):
    cache = Path(cache)
    receipt = json.loads((cache / 'callback-chain-staging.json').read_text(encoding='utf-8'))
    if (not isinstance(receipt, dict) or set(receipt) != {'format', 'sources'}
            or receipt['format'] != 1 or not isinstance(receipt['sources'], list)
            or len(receipt['sources']) != len(SOURCES)):
        raise ValueError('Invalid callback chain staging receipt')
    for record, (relative, expected, before, after) in zip(receipt['sources'], SOURCES):
        if (not isinstance(record, dict) or set(record) != {'source', 'before_sha256', 'after_sha256'}
                or record['source'] != relative or record['before_sha256'] != expected):
            raise ValueError('Invalid callback chain source identity')
        data = _owned(cache, relative).read_bytes()
        if data.count(after.encode()) != 1:
            raise ValueError('Callback chain boundary changed: ' + relative)
        original = data.replace(after.encode(), before.encode())
        if (hashlib.sha256(data).hexdigest() != record['after_sha256']
                or hashlib.sha256(original).hexdigest() != expected):
            raise ValueError('Callback chain source bytes changed: ' + relative)
    return receipt
