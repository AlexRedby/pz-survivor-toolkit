"""Native VRO repair/salvage effects, peer state and a separately restored save."""
from pathlib import Path
import re
import shutil

from .. import receipts
from ..mod_selection import metadata, mod_ids

SUITE = 'vro-gameplay'
MARKER = '[VRO_GAMEPLAY] '
PHASES = ('repair-cancel', 'repair-complete', 'salvage-cancel', 'salvage-complete')
PROJECT = Path(__file__).resolve().parents[3]
MODS = mod_ids(metadata(PROJECT / 'SurvivorQoL-selected.ini')['Mods'])
SUPPORT = ('QueueEnergyPlacement.lua', 'QueueFixtureWorldCleanup.lua', 'QueueFixtureItemCleanup.lua',
           'QueueFixtureSession.lua')
LIMITS = ['Native menu callbacks and ordinary timed actions; no physical pointer-input claim.',
          'SP or local menu Host with the selected locked pack; no dedicated server or WAN claim.']


def definitions():
    return {SUITE: dict(status='ready', clients=2, default_mods=list(MODS),
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                    languages=['EN', 'RU'], modes=['toolkit', 'native']) for case in ('bank', 'reload')], limits=LIMITS)}


def validate(selection):
    options = selection.get('options', {})
    kind = selection.get('kind')
    if (selection.get('cases') not in (['bank'], ['reload']) or kind not in ('sp', 'mp')
            or selection.get('mode') not in ('toolkit', 'native') or selection.get('languages') != (['EN'] if kind == 'sp' else ['EN', 'RU'])
            or type(selection.get('clients')) is not int or selection['clients'] != (1 if kind == 'sp' else 2)
            or selection.get('mods') != MODS or type(options) is not dict
            or not isinstance(options.get('pack_lock'), str) or not Path(options['pack_lock']).is_absolute()
            or any(options.get(key) for key in ('seed_run', 'startup_connection'))
            or kind == 'mp' and options.get('mp_host') is not True
            or kind == 'sp' and options.get('mp_host')
            or bool(options.get('world_template')) != (selection['cases'] == ['reload'])):
        raise ValueError('VRO gameplay requires bank/reload, explicit queue mode, full locked selected pack, one EN SP actor or EN/RU menu-Host clients')
    if selection['cases'] == ['reload']:
        template = options['world_template']
        if not isinstance(template, str) or not Path(template).is_absolute():
            raise ValueError('VRO reload requires an absolute sealed world_template from its bank')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', *[root / 'support' / name for name in SUPPORT]]


def _startup(text, case):
    anchor = ' if config.kind==\'sp\' then\n  if started and isIngameState()'
    replacement = ''' if config.kind=='sp' then
  local reader=getFileReader('vro-gameplay-exit.txt',false)
  local exit=reader and reader:readLine();if reader then reader:close() end
  if exit and exit~='' then return end
  if started and isIngameState()'''
    if text.count(anchor) != 1:
        raise ValueError('Common SP startup guard changed')
    text = text.replace(anchor, replacement)
    if case == 'bank':
        return text
    begin = "  getWorld():setGameMode('Sandbox');getWorld():setWorld('QueueStartup');getWorld():setMap('Muldraugh, KY')"
    end = "  MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})"
    start, stop = text.index(begin), text.index(end, text.index(begin)) + len(end)
    return text[:start] + "  MainScreen.continueLatestSave('Sandbox','QueueStartup')" + text[stop:]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for package in (SUITE, 'startup'):
            for path in sorted((root / package).rglob('*.lua')):
                target = lua / path.relative_to(root / package)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
        for path in [root / 'health/shared/QueueHealthEvents.lua', *[root / 'support' / name for name in SUPPORT]]:
            target = lua / 'shared' / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        (lua / 'shared/QueueVROGameplayConfig.lua').write_text("return {case='" + selection['cases'][0] + "'}\n")
        if selection['kind'] == 'sp':
            startup = lua / 'client/ZZStartup.lua'
            startup.write_text(_startup(startup.read_text(), selection['cases'][0]))
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=[MARKER + 'FAIL '], sandbox={'Zombies': 6}, client_launch_stagger_seconds=8)


def _need(value, reason):
    if not value:
        raise ValueError(reason)


def _keys(value, keys, name):
    _need(type(value) is dict and set(value) == set(keys), 'invalid exact ' + name + ' envelope')


def _integer(value):
    return type(value) is int and -2147483648 <= value <= 2147483647


def _number(value):
    return type(value) in (int, float)


def _same(left, right):
    if type(left) is dict and type(right) is dict:
        return set(left) == set(right) and all(_same(left[key], right[key]) for key in left)
    if type(left) is list and type(right) is list:
        return len(left) == len(right) and all(_same(a, b) for a, b in zip(left, right))
    if _number(left) and _number(right):
        return left == right
    return type(left) is type(right) and left == right


def _items(values, name):
    _need(type(values) is list, 'invalid ' + name + ' item list')
    seen = set()
    for row in values:
        _keys(row, ('id', 'fullType'), name + ' item')
        _need(_integer(row['id']) and row['id'] not in seen and type(row['fullType']) is str and row['fullType'],
              'invalid or repeated ' + name + ' item identity')
        seen.add(row['id'])
    return {row['id']: row['fullType'] for row in values}


def _world(value, key, multiplayer):
    _need(type(value) is dict and value.get('vehicleKey') == key and _integer(value.get('vehicleID'))
          and (not multiplayer or value['vehicleID'] >= 0) and type(value.get('removed')) is bool,
          'invalid ' + key + ' world identity')
    fields = {'vehicleKey', 'vehicleID', 'removed', 'ground'}
    if not value['removed']:
        fields |= {'itemID', 'condition', 'itemCondition', 'hbr'}
        _need(_integer(value.get('itemID')) and all(_integer(value.get(name)) for name in ('condition', 'itemCondition', 'hbr'))
              and 0 <= value['condition'] <= 100 and value['itemCondition'] == value['condition'] and value['hbr'] >= 0,
              'invalid installed hood world state')
    _keys(value, fields, key + ' world')
    _items(value['ground'], key + ' world ground')


def _repair(before, after, mode):
    fields = {'vehicleID', 'vehicleKey', 'partID', 'itemID', 'itemType', 'condition', 'itemCondition', 'itemMax',
              'hbr', 'metal', 'torch', 'mask', 'xp', 'levels'}
    for row in (before, after):
        _keys(row, fields, 'repair observation')
        _need(row['vehicleKey'] == 'repair' and _integer(row['vehicleID']) and row['partID'] == 'EngineDoor'
              and _integer(row['itemID']) and type(row['itemType']) is str and row['itemType']
              and all(_integer(row[name]) for name in ('condition', 'itemCondition', 'itemMax', 'hbr')),
              'invalid repair target identity')
        _keys(row['xp'], ('Mechanics', 'MetalWelding'), 'repair XP')
        _keys(row['levels'], ('Mechanics', 'MetalWelding'), 'repair levels')
        _need(all(_number(value) and value >= 0 for value in row['xp'].values())
              and all(type(value) is int and value == 4 for value in row['levels'].values()), 'invalid repair skill state')
        _need(type(row['metal']) is list and len(row['metal']) == 2, 'invalid owned repair material set')
        for item in row['metal']:
            _keys(item, ('id', 'present', 'fullType') if item.get('present') is True else ('id', 'present'), 'repair material')
            _need(_integer(item['id']) and type(item['present']) is bool
                  and (not item['present'] or item['fullType'] == 'Base.SheetMetal'), 'invalid repair material identity')
        _need(row['metal'][0]['id'] != row['metal'][1]['id'], 'duplicated repair material')
        _keys(row['torch'], ('id', 'present', 'fullType', 'uses'), 'repair torch')
        _need(_integer(row['torch']['id']) and row['torch']['present'] is True and row['torch']['fullType'] == 'Base.BlowTorch'
              and _integer(row['torch']['uses']) and row['torch']['uses'] >= 0, 'invalid repair torch')
        _keys(row['mask'], ('id', 'present', 'fullType', 'condition'), 'repair mask')
        _need(_integer(row['mask']['id']) and row['mask']['present'] is True and row['mask']['fullType'] == 'Base.WeldingMask'
              and _integer(row['mask']['condition']) and 0 <= row['mask']['condition'] <= 100, 'invalid repair mask')
    _need(all(_same(before[key], after[key]) for key in ('vehicleID', 'vehicleKey', 'partID', 'itemID', 'itemType', 'itemMax', 'mask', 'levels')),
          'repair target or kept item was replaced')
    _need(before['condition'] == before['itemCondition'] == 40 and before['itemMax'] == 100 and before['hbr'] == 0,
          'repair initial condition/history differs')
    _need(all(row['present'] is True for row in before['metal']) and before['torch']['uses'] >= 3,
          'repair materials/fuel were not initially owned')
    if mode == 'cancel':
        _need(_same(before, after), 'cancelled repair changed condition/resources/XP')
    else:
        _need(after['condition'] == after['itemCondition'] == 76 and after['hbr'] == 1,
              'repair condition/history effect differs')
        _need([row['id'] for row in before['metal']] == [row['id'] for row in after['metal']]
              and all(row['present'] is False for row in after['metal']), 'repair did not consume exact owned sheets')
        _need(before['torch']['uses'] - after['torch']['uses'] == 3, 'repair torch cost differs')
        _need(all(after['xp'][name] > before['xp'][name] for name in before['xp']), 'repair XP was not awarded')


def _salvage(before, after, mode):
    fields = {'vehicleID', 'vehicleKey', 'removed', 'torchID', 'torchPresent', 'torchUses',
              'torchContainerType', 'torchInRoot', 'primaryID', 'secondaryID', 'maskID', 'maskWornID',
              'metalWeldingXP', 'x', 'y', 'z', 'ground'}
    for row in (before, after):
        _keys(row, fields, 'salvage observation')
        _need(row['vehicleKey'] == 'salvage' and all(_integer(row[key]) for key in
              ('vehicleID', 'torchID', 'torchUses', 'primaryID', 'secondaryID', 'maskID', 'maskWornID', 'x', 'y', 'z'))
              and type(row['removed']) is bool and row['torchPresent'] is True and row['torchInRoot'] is True
              and type(row['torchContainerType']) is str and _number(row['metalWeldingXP']) and row['metalWeldingXP'] >= 0,
              'invalid salvage identity/resource state')
        _items(row['ground'], 'salvage ground')
    _need(all(_same(before[key], after[key]) for key in ('vehicleID', 'vehicleKey', 'torchID', 'maskID', 'x', 'y', 'z',
                                                       'torchContainerType')),
          'salvage target/torch/container identity changed')
    _need(before['removed'] is False and before['torchUses'] >= 10, 'invalid salvage initial vehicle/fuel')
    old, new = _items(before['ground'], 'salvage initial'), _items(after['ground'], 'salvage final')
    _need(all(new.get(key) == value for key, value in old.items()), 'salvage changed preexisting ground items')
    added = [{'id': key, 'fullType': value} for key, value in new.items() if key not in old]
    if mode == 'cancel':
        _need(after['removed'] is False and after['torchUses'] == before['torchUses']
              and after['metalWeldingXP'] == before['metalWeldingXP'] and not added,
              'cancelled salvage changed vehicle/resources/output/XP')
    else:
        _need(after['removed'] is True and before['torchUses'] - after['torchUses'] == 10
              and after['metalWeldingXP'] > before['metalWeldingXP'] and added,
              'salvage removal/fuel/output/XP effect differs')
    return added


def _phase(row, phase, index, multiplayer):
    _keys(row, ('phase', 'index', 'before', 'after', 'world', 'action'), 'authoritative phase')
    _need(row['phase'] == phase and type(row['index']) is int and row['index'] == index, 'authoritative phases are missing, duplicated or out of order')
    key, mode = phase.split('-')
    before, after, action = row['before'], row['after'], row['action']
    _world(row['world'], key, multiplayer)
    action_fields = {'mode', 'vehicleID', 'vehicleKey', 'before', 'after', 'started', 'nativeDuration', 'cancelled', 'menuCallback'}
    action_fields |= {'recipeDuration'} if key == 'repair' else {'sourceDuration', 'drops', 'luaActions', 'nativeActions', 'hasPath'}
    _keys(action, action_fields, 'native action')
    _need(action['mode'] == mode and action['vehicleID'] == after.get('vehicleID') == row['world']['vehicleID']
          and action['vehicleKey'] == key and action['started'] is True and action['menuCallback'] is True
          and action['cancelled'] is (mode == 'cancel') and _number(action['nativeDuration'])
          and action['nativeDuration'] > 1 and _same(action['before'], before) and _same(action['after'], after),
          'native action evidence/authoritative effect identity differs')
    if key == 'repair':
        _need(type(action['recipeDuration']) is int and action['recipeDuration'] == 280
              and action['nativeDuration'] >= 280, 'repair duration was shortened')
        _repair(before, after, mode)
        _need(row['world']['removed'] is False and all(row['world'][name] == after[name] for name in ('itemID', 'condition', 'itemCondition', 'hbr')),
              'repair world differs from the authoritative installed item')
    else:
        _need(type(action['sourceDuration']) is int and action['sourceDuration'] == 1920 and action['nativeDuration'] >= 1920
              and action['luaActions'] == 0 and type(action['luaActions']) is int
              and action['nativeActions'] == 0 and type(action['nativeActions']) is int and action['hasPath'] is False,
              'salvage duration or drained native state differs')
        added = _salvage(before, after, mode)
        _need(_same(action['drops'], added) and row['world']['removed'] is after['removed']
              and _same(row['world']['ground'], after['ground']), 'salvage output/world receipt differs')


def _events(text):
    # CoopMaster forwarding cannot satisfy the receiving process's own checks.
    rows = []
    for line in text.splitlines():
        if 'SERVER:' in line or '[CoopMaster]' in line:
            continue
        offset = line.find(MARKER)
        if offset < 0:
            continue
        payload = line[offset + len(MARKER):]
        _need(not payload.startswith('FAIL '), 'native VRO failure: ' + payload)
        event, separator, data = payload.partition(' ')
        _need(separator and re.fullmatch('[A-Z_]+', event), 'malformed VRO event')
        rows.append((event, receipts.decode_object(data)))
    return rows


def _one(events, event):
    rows = [row for name, row in events if name == event]
    _need(len(rows) == 1, 'missing or duplicate ' + event)
    return rows[0]


def complete(selection, role, text):
    try:
        events = _events(text)
        _need(_one(events, 'COMPLETE') == {'case': selection['cases'][0], 'role': role}, 'incorrect completion identity')
        if selection['kind'] == 'sp':
            _need(_one(events, 'SAVED_RETURN') == dict(case=selection['cases'][0], role='client1', saved=True, returned=True),
                  'SP fixture did not actually save and return to the menu')
            names = [name for name, _ in events]
            _need(names.index('SAVED_RETURN') < names.index('COMPLETE'), 'completion preceded saved menu return')
        return True
    except (ValueError, KeyError, TypeError):
        return False


def _worlds(value, multiplayer):
    _keys(value, ('repair', 'salvage'), 'world pair')
    for key in ('repair', 'salvage'):
        _world(value[key], key, multiplayer)


def _actor(value):
    _keys(value, ('primary', 'secondary', 'x', 'y', 'z', 'xp', 'worn', 'items', 'total'), 'persisted actor')
    _need(all(value[key] is False or _integer(value[key]) for key in ('primary', 'secondary'))
          and all(_number(value[key]) for key in ('x', 'y', 'z', 'total')), 'invalid actor state')
    _keys(value['xp'], ('Mechanics', 'MetalWelding'), 'persisted actor XP')
    for row in value['xp'].values():
        _keys(row, ('xp', 'level'), 'persisted skill')
        _need(_number(row['xp']) and type(row['level']) is int, 'invalid persisted skill state')
    _need(type(value['worn']) is list, 'invalid persisted worn items')
    worn_ids = set()
    for row in value['worn']:
        _keys(row, ('id', 'location'), 'persisted worn slot')
        _need(_integer(row['id']) and row['id'] not in worn_ids
              and type(row['location']) is str and row['location'], 'invalid persisted worn identity/slot')
        worn_ids.add(row['id'])
    return _items(value['items'], 'persisted actor')


def _bank(logs, selection):
    multiplayer = selection['kind'] == 'mp'
    authority = logs['server' if multiplayer else 'client1']
    phases = [row for event, row in authority if event == 'AUTHORITY_AFTER']
    _need(len(phases) == len(PHASES), 'missing or duplicate authoritative gameplay phases')
    for index, (phase, row) in enumerate(zip(PHASES, phases), 1):
        _phase(row, phase, index, multiplayer)
    for previous, following in ((phases[0], phases[1]), (phases[2], phases[3])):
        _need(_same(previous['after'], following['before']), 'same-family authority phase continuity differs')
    checkpoint = _one(authority, 'CHECKPOINT')
    fields = {'retainedForReload', 'actor', 'original', 'worlds', 'owned', 'clientOriginals'}
    _keys(checkpoint, fields, 'checkpoint')
    original_items = _actor(checkpoint['original'])
    _need(checkpoint['retainedForReload'] is True, 'fixture state was not retained for reload')
    final_items = _actor(checkpoint['actor'])
    owned_items = _items(checkpoint['owned'], 'checkpoint owned'); _worlds(checkpoint['worlds'], multiplayer)
    clients = ['client1', 'client2'] if multiplayer else ['client1']
    _keys(checkpoint['clientOriginals'], clients, 'checkpoint client originals')
    for role in clients:
        items = _actor(checkpoint['clientOriginals'][role])
        _need(not set(items) & set(owned_items), role + ': original actor already contains fixture-owned IDs')
    first_original = checkpoint['clientOriginals']['client1']
    _need(_same(_actor_core(first_original), _actor_core(checkpoint['original']))
          and all(_same(first_original[axis], checkpoint['original'][axis]) for axis in ('x', 'y', 'z')),
          'checkpoint authority/client1 original actor differs')
    repair, salvage = phases[1]['after'], phases[3]['after']
    kept = {repair['torch']['id']: 'Base.BlowTorch', repair['mask']['id']: repair['mask']['fullType'], salvage['torchID']: 'Base.BlowTorch'}
    consumed = {row['id']: 'Base.SheetMetal' for row in phases[0]['before']['metal']}
    _need(len(kept) == 3 and not set(kept) & set(consumed) and not set(original_items) & (set(kept) | set(consumed))
          and owned_items == {**kept, **consumed} and final_items == {**original_items, **kept},
          'checkpoint ownership/inventory does not match exact consumed and kept fixture inputs')
    _need(checkpoint['actor']['xp']['Mechanics']['xp'] == repair['xp']['Mechanics']
          and checkpoint['actor']['xp']['MetalWelding']['xp'] == salvage['metalWeldingXP'], 'checkpoint actor XP differs from final effects')
    _need(_same(checkpoint['worlds']['repair'], phases[1]['world'])
          and _same(checkpoint['worlds']['salvage'], phases[3]['world']), 'checkpoint differs from final authoritative effects')
    names = [event for event, _ in authority]
    _need(names.index('CHECKPOINT') > max(index for index, event in enumerate(names) if event == 'AUTHORITY_AFTER'),
          'checkpoint preceded final gameplay effects')
    for role in clients:
        if multiplayer:
            _need(not any(event in ('AUTHORITY_AFTER', 'CHECKPOINT') for event, _ in logs[role]), role + ': foreign authority receipts')
            _need(_one(logs[role], 'CHECKPOINT_PEER') == dict(role=role, retainedForReload=True), role + ': missing checkpoint acknowledgement')
        peers = [row for event, row in logs[role] if event == 'PEER']
        _need(len(peers) == len(PHASES), role + ': missing or duplicate peer phases')
        for index, (peer, phase) in enumerate(zip(peers, phases), 1):
            _keys(peer, ('phase', 'index', 'role', 'world'), 'peer phase')
            _need(peer['role'] == role and peer['phase'] == phase['phase'] and type(peer['index']) is int
                  and peer['index'] == index and _same(peer['world'], phase['world']), role + ': peer target/effect differs')
        local_names = [event for event, _ in logs[role]]
        _need(local_names.index('COMPLETE') > max(index for index, event in enumerate(local_names) if event == 'PEER'),
              role + ': completion preceded peer state')
        if multiplayer:
            _need(local_names.index('CHECKPOINT_PEER') > max(index for index, event in enumerate(local_names) if event == 'PEER')
                  and local_names.index('CHECKPOINT_PEER') < local_names.index('COMPLETE'), role + ': checkpoint acknowledgement order differs')
    return dict(phases=phases, checkpoint=checkpoint)


def _seed(selection):
    from .. import report, worlds
    template = Path(selection['options']['world_template'])
    _need(not template.is_symlink(), 'reload template cannot be a symlink')
    world = report.read_json(template / 'world.json')
    roles = ['server', 'client1', 'client2'] if selection['kind'] == 'mp' else ['client1']
    _need(world.get('source_suite') == SUITE and world.get('source_cases') == ['bank']
          and world.get('kind') == selection['kind'] and world.get('roles') == roles
          and world.get('mp_host', False) is (selection['kind'] == 'mp') and world.get('mods') == selection['mods'],
          'reload template does not belong to the matching VRO bank')
    source = worlds.completed_source_run(world)
    _need(not source.is_symlink(), 'reload bank run cannot be a symlink')
    original = report.read_json(source / 'selection.json')
    result = report.read_json(source / 'report.json')
    execution = report.read_json(source / 'execution.json')
    _need(original.get('suite') == SUITE and original.get('cases') == ['bank']
          and original.get('mode') == selection['mode']
          and original.get('kind') == selection['kind'] and original.get('mods') == selection['mods']
          and result.get('status') == 'passed' and result.get('functional', {}).get('status') == 'passed'
          and result.get('runtime', {}).get('status') in ('clean', 'background-only')
          and result.get('provenance', {}).get('verified') is True and execution.get('status') == 'completed',
          'reload requires a completed clean verified VRO bank')
    _need(not report.verify_manifest(source, 'source-manifest.json', True)
          and not report.verify_manifest(source, 'snapshot-hashes.json'), 'reload bank evidence changed')
    audit = report.audit_logs(source, roles, native_game_sha256=report.verified_game_sha256(source, True))
    _need(all(row['available'] and not row['microphone'] and not row['fatal_count'] and not row['unclassified_count']
              for row in audit.values()), 'reload bank current native log audit is unsafe or stale')
    seed = verify(source, original, {})
    _need(not seed['issues'], 'reload bank native receipts are incomplete: ' + '; '.join(seed['issues']))
    return seed['evidence']


def _role_one(events, event, role):
    rows = [row for name, row in events if name == event and row.get('role') == role]
    _need(len(rows) == 1, 'missing or duplicate ' + role + ' ' + event)
    return rows[0]


def _actor_core(value):
    result = {key: item for key, item in value.items() if key not in ('x', 'y', 'z')}
    result['items'] = sorted(value['items'], key=lambda row: row['id'])
    result['worn'] = sorted(value['worn'], key=lambda row: row['id'])
    return result


def _world_core(value):
    return {key: item for key, item in value.items() if key != 'vehicleID'}


def _reload(logs, selection):
    multiplayer = selection['kind'] == 'mp'
    authority = logs['server' if multiplayer else 'client1']
    for role, events in logs.items():
        expected_roles = ['authority'] if role == 'server' else (['authority', 'client1'] if not multiplayer else [role])
        for event in ('RELOADED', 'CLEANUP'):
            _need([row.get('role') for name, row in events if name == event] == expected_roles,
                  role + ': foreign, duplicate or out-of-order reload/cleanup roles')
    seed = _seed(selection)
    checkpoint = seed['checkpoint']
    _need('original' in checkpoint and 'clientOriginals' in checkpoint,
          'reload bank lacks original actor restoration evidence')
    restored = _role_one(authority, 'RELOADED', 'authority')
    _keys(restored, ('role', 'actor', 'worlds', 'owned', 'resources'), 'authority reload')
    _need(restored['role'] == 'authority', 'reload authority role differs')
    _actor(restored['actor']); _items(restored['owned'], 'restored owned'); _worlds(restored['worlds'], multiplayer)
    _need(_same(_actor_core(restored['actor']), _actor_core(checkpoint['actor']))
          and _same(restored['owned'], checkpoint['owned']), 'reload actor/owned IDs differ from the actual saved bank')
    for key in ('repair', 'salvage'):
        _need(_same(_world_core(restored['worlds'][key]), _world_core(checkpoint['worlds'][key])),
              'reload world item identity/effect differs from the saved bank: ' + key)
    repair, salvage = seed['phases'][1]['after'], seed['phases'][3]['after']
    expected_resources = dict(repairTorch=dict(id=repair['torch']['id'], fullType='Base.BlowTorch', uses=repair['torch']['uses']),
        salvageTorch=dict(id=salvage['torchID'], fullType='Base.BlowTorch', uses=salvage['torchUses']),
        mask=dict(id=repair['mask']['id'], fullType=repair['mask']['fullType']),
        metal=[dict(id=row['id'], present=False) for row in repair['metal']])
    _need(_same(restored['resources'], expected_resources), 'reload paid torch/material/kept mask state differs')
    cleanup = _role_one(authority, 'CLEANUP', 'authority')
    _keys(cleanup, ('role', 'restored', 'actor', 'vehicles', 'items', 'ground', 'worlds'), 'authority cleanup')
    _need(cleanup['restored'] is True, 'missing actual authority cleanup/restoration')
    _actor(cleanup['actor']); _worlds(cleanup['worlds'], multiplayer)
    _need(_same(_actor_core(cleanup['actor']), _actor_core(checkpoint['original']))
          and all(abs(cleanup['actor'][axis] - checkpoint['original'][axis]) <= .001 for axis in ('x', 'y', 'z')),
          'cleanup did not restore original actor inventory/equipment/XP/fractional position')
    _keys(cleanup['vehicles'], ('removed',), 'vehicle cleanup')
    expected_vehicle = dict(vehicleKey='repair', installedID=repair['itemID'], vehicleID=restored['worlds']['repair']['vehicleID'])
    _need(_same(cleanup['vehicles']['removed'], [expected_vehicle]), 'cleanup did not remove exact restored vehicle identity')
    surviving = sorted([repair['torch']['id'], repair['mask']['id'], salvage['torchID']])
    _keys(cleanup['items'], ('removedIds', 'removalCalls', 'noticeAttempts', 'recoveries'), 'item cleanup journal')
    _need(_same(cleanup['items']['removedIds'], surviving) and type(cleanup['items']['removalCalls']) is int
          and cleanup['items']['removalCalls'] == len(surviving) and type(cleanup['items']['noticeAttempts']) is int
          and cleanup['items']['noticeAttempts'] == (len(surviving) if multiplayer else 0)
          and cleanup['items']['recoveries'] == [], 'cleanup inventory removal/publication journal differs')
    drops = seed['phases'][3]['action']['drops']
    ground = cleanup['ground']
    _keys(ground, ('publicationAttempts', 'removedObjects', 'publicationUncertain', 'recoveries', 'states'), 'ground cleanup journal')
    _need(type(ground['publicationAttempts']) is int and ground['publicationAttempts'] == len(drops)
          and type(ground['removedObjects']) is int and ground['removedObjects'] == len(drops)
          and ground['publicationUncertain'] is False and ground['recoveries'] == []
          and type(ground['states']) is list and len(ground['states']) == len(drops),
          'cleanup ground removal/publication journal differs')
    indices = set()
    for state in ground['states']:
        _keys(state, ('index', 'status'), 'ground removal state')
        _need(type(state['index']) is int and state['index'] >= 0 and state['index'] not in indices
              and state['status'] in ('removed', 'published'), 'invalid exact ground cleanup state')
        indices.add(state['index'])
    baseline = dict(repair=seed['phases'][0]['world']['ground'], salvage=seed['phases'][2]['before']['ground'])
    for key in ('repair', 'salvage'):
        actual = cleanup['worlds'][key]
        _need(actual['removed'] is True and actual['vehicleID'] == restored['worlds'][key]['vehicleID']
              and _same(actual['ground'], baseline[key]), 'cleanup changed unowned ground or retained fixture objects: ' + key)
    authority_names = [(event, row.get('role')) for event, row in authority]
    _need(authority_names.index(('RELOADED', 'authority')) < authority_names.index(('CLEANUP', 'authority')),
          'authority cleanup preceded reload verification')
    peer_cleanups = {}
    for role in (['client1', 'client2'] if multiplayer else ['client1']):
        peer_reload = [row for event, row in logs[role] if event == 'RELOADED' and row.get('role') == role]
        _need(len(peer_reload) == 1, role + ': missing/duplicate restored peer state')
        _keys(peer_reload[0], ('role', 'worlds'), 'peer reload')
        _need(_same(peer_reload[0]['worlds'], restored['worlds']), role + ': restored peer identity differs')
        peer_cleanup = [row for event, row in logs[role] if event == 'CLEANUP' and row.get('role') == role]
        _need(len(peer_cleanup) == 1, role + ': missing/duplicate peer cleanup')
        peer = peer_cleanup[0]
        _keys(peer, ('role', 'worlds', 'actor', 'restored', 'ownedAbsent'), 'peer cleanup')
        _need(peer['restored'] is True and peer['ownedAbsent'] is True,
              role + ': cleanup lacks actual actor restoration/owned absence')
        _worlds(peer['worlds'], multiplayer)
        peer_items = _actor(peer['actor'])
        _need(not set(peer_items) & {row['id'] for row in checkpoint['owned']},
              role + ': cleanup peer retained fixture-owned inventory')
        original = checkpoint['clientOriginals'][role]
        _need(_same(_actor_core(peer['actor']), _actor_core(original))
              and all(abs(peer['actor'][axis] - original[axis]) <= .001 for axis in ('x', 'y', 'z')),
              role + ': cleanup did not restore own original inventory/equipment/XP/fractional position')
        _need(_same(peer['worlds'], cleanup['worlds']), role + ': cleanup peer state differs from actual authority')
        peer_cleanups[role] = peer
        names = [(event, row.get('role')) for event, row in logs[role]]
        _need(names.index(('RELOADED', role)) < names.index(('CLEANUP', role)) < names.index(('COMPLETE', role)),
              role + ': invalid reload/cleanup/completion order')
    return dict(restored=restored, cleanup=cleanup, peerCleanups=peer_cleanups)


def verify(root, selection, catalog):
    issues, evidence = [], {}
    roles = ['server', 'client1', 'client2'] if selection['kind'] == 'mp' else ['client1']
    try:
        logs = {role: _events((Path(root) / (role + '-launch.log')).read_text(errors='replace')) for role in roles}
        for role in roles:
            if role != 'server':
                text = (Path(root) / (role + '-launch.log')).read_text(errors='replace')
                _need(complete(selection, role, text), role + ': incomplete native VRO lifecycle')
        evidence = _bank(logs, selection) if selection['cases'] == ['bank'] else _reload(logs, selection)
    except (OSError, ValueError, TypeError, KeyError, IndexError) as error:
        issues.append(str(error))
    return dict(issues=issues, outcomes=[dict(actor=role, case=selection['cases'][0],
                status='failed' if issues else 'passed', reason='; '.join(issues)) for role in roles if role != 'server'],
                evidence=dict(evidence, limits=LIMITS))
