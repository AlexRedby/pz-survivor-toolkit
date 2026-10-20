"""Native fifteen Engine Parts drop from root inventory to a real car trunk."""
import json
from pathlib import Path
import re
from . import craft

MODS = craft.MODS
MARKER = '[INVENTORY_TRANSFER_TEST] '


def definitions():
    return {'inventory-transfer': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
        'cases': [dict(id='trunk-15', producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       languages=['EN'], modes=['native', 'toolkit'])]}}


def validate(selection):
    if (selection.get('cases') != ['trunk-15'] or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('clients') != 1
            or selection.get('languages') != ['EN'] or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Inventory transfer requires fresh one-client SP/Host, trunk-15, EN and Toolkit/Java patches')
    if selection['kind'] == 'mp' and not selection.get('options', {}).get('mp_host'):
        raise ValueError('Inventory transfer MP uses native menu Host')
    if type(selection.get('options', {}).get('inventory_transfer_density', False)) is not bool:
        raise ValueError('inventory_transfer_density must be boolean')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'inventory-transfer').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', *sorted((root / 'startup').rglob('*.lua')),
            *sorted((root / 'craft/scripts').rglob('*.txt'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    craft.stage_common(project, output, game, jdk, selection, locations, runtime)


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(MARKER) + r'COMPLETE(?:\s|$)', text)) == 1


def _authority(text):
    return [(match[1], json.loads(match[2])) for match in re.finditer(
        re.escape(MARKER) + r'(PREPARED|VERIFIED)\s+([^\n]*)', text)]


def _inventory(value):
    return (type(value) is dict
            and all(type(value.get(key)) is int and value[key] >= 0 for key in ('rootItems', 'trunkItems'))
            and all(type(value.get(key)) in (int, float) and value[key] >= 0
                    for key in ('rootWeight', 'trunkWeight', 'rootCapacity', 'trunkCapacity'))
            and value['rootWeight'] <= value['rootCapacity'] and value['trunkWeight'] <= value['trunkCapacity'])


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    client = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
    rows, raw, issues = events(client), _authority(authority), []
    if not complete(selection, 'client1', client):
        issues.append('Missing or duplicate inventory transfer completion')
    if ([row['event'] for row in rows] != ['setup', 'case', 'complete']
            or any(not craft._matches(row, dict(suite='inventory-transfer', actor='client1', kind=selection['kind'], mode=selection['mode'])) for row in rows)):
        issues.append('Inventory transfer event order/context differs')
    for event, expected in [('setup', dict(cases=['trunk-15'], expected=1, nativeDurations=True,
                                           queueEnabled=selection['mode']=='toolkit')),
                            ('complete', dict(cases=['trunk-15'], expected=1, performed=1, failed=0, skipped=0))]:
        records = [row for row in rows if row['event'] == event]
        if len(records) != 1 or not craft._matches(records[0], expected):
            issues.append('Inventory transfer ' + event + ' differs')
    if [(marker, value.get('case')) for marker, value in raw] != [('PREPARED', 'trunk-15'), ('VERIFIED', 'trunk-15')]:
        issues.append('Inventory transfer authority order differs')
    prep = next((value for marker, value in raw if marker == 'PREPARED'), {})
    receipt = next((value for marker, value in raw if marker == 'VERIFIED'), {})
    row = next((value for value in rows if value.get('event') == 'case'), {})
    original = prep.get('items', [])
    identities = [item.get('id') for item in original if type(item) is dict]
    if (not craft._ids(identities, 15) or len(original) != 15
            or any(not craft._matches(item, dict(kind='Base.EngineParts')) for item in original)
            or not craft._matches(prep, dict(case='trunk-15', script='Base.CarNormal', part='TruckBed', count=15))
            or type(prep.get('vehicleId')) is not int or prep['vehicleId'] < 0):
        issues.append('Inventory transfer preparation identities/car differ')
    final = receipt.get('items', [])
    if (not craft._matches(receipt, {key: prep.get(key) for key in ('case', 'script', 'part', 'vehicleId', 'destinationType', 'count')})
            or len(final) != 15 or any(not craft._matches(item, dict(id=identity, kind='Base.EngineParts', count=1, endpoint='trunk'))
                                     for item, identity in zip(final, identities))):
        issues.append('Authoritative exact fifteen trunk endpoints/uniqueness differ')
    if (not craft._matches(row, dict(id='trunk-15', status='passed', queueIdle=True, clientIdentityVerified=True, **receipt))
            or type(row.get('settleMilliseconds')) not in (int, float) or row['settleMilliseconds'] < 3000):
        issues.append('Client result/authority/settle differs')
    command = row.get('command', {})
    if (not craft._matches(command, dict(dropDispatched=True, count=15, transferProgress=True, nativeDurations=True,
                                        source='root', destination='trunk', queueEmptyBefore=True, selectedItems=15))
            or sorted(command.get('enqueuedIds', [])) != sorted(identities)
            or type(command.get('activeSamples')) is not int or command['activeSamples'] <= 0
            or type(command.get('progressDuration')) not in (int, float) or command['progressDuration'] <= 0
            or type(command.get('nativeDuration')) not in (int, float)
            or (command['nativeDuration'] != -1 if selection['kind']=='mp' else command['nativeDuration'] <= 0)):
        issues.append('Actual native drop/admission/active timing evidence differs')
    performance = row.get('performance', {})
    frames, calls = performance.get('frames', {}), performance.get('calls', {})
    if not craft._matches(performance, dict(clock='getTimestampMs', inclusive=True, nativeUpdateUnmodified=True)):
        issues.append('Profiling method/provenance differs')
    dense = selection.get('options', {}).get('inventory_transfer_density', False)
    if dense:
        filler = dict(kind='Base.Paperclip', root=500, trunk=1000)
        initial, settled = prep.get('inventory', {}), receipt.get('inventory', {})
        profile_inventory = performance.get('inventory', {})
        if (not craft._matches(prep, dict(density=True, filler=filler))
                or not craft._matches(receipt, dict(density=True, filler=dict(filler, identitiesVerified=True)))
                or not _inventory(initial) or not _inventory(settled)
                or initial.get('rootItems', 0) < 515 or initial.get('trunkItems') != 1000
                or settled.get('rootItems') != initial.get('rootItems', 0)-15 or settled.get('trunkItems') != 1015
                or not _inventory(profile_inventory.get('idle')) or not _inventory(profile_inventory.get('settled'))
                or any(profile_inventory.get(phase, {}).get(key) != source.get(key)
                       for phase, source in [('idle', initial), ('settled', settled)] for key in ('rootItems', 'trunkItems'))):
            issues.append('Dense inventory preparation/capacity/unchanged filler identity evidence differs')
    elif prep.get('density') or receipt.get('density') or prep.get('filler') or receipt.get('filler'):
        issues.append('Unexpected dense inventory fixture without option')
    for phase in ('idle', 'running'):
        value = frames.get(phase, {})
        if (type(value.get('samples')) is not int or value['samples'] < 2
                or any(type(value.get(key)) not in (int, float) or value[key] < 0
                       for key in ('totalMs', 'meanMs', 'p50Ms', 'p95Ms', 'maxMs'))
                or not any(label.startswith('pane.') and entry.get('calls', 0) > 0 for label, entry in calls.get(phase, {}).items())):
            issues.append('Missing measured UI frame/pane evidence: ' + phase)
    if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native inventory transfer fixture failed')
    return dict(issues=issues, outcomes=[dict(actor='client1', case='trunk-15', status='failed' if issues else 'passed',
                 reason='; '.join(issues), outcome=dict(row, effectsVerified=not issues,
                 serverAuthorityVerified=not issues and selection['kind']=='mp'))], evidence={'profile': performance, 'limits': [
        'Actual destination pane onMouseUp drop callback with physical item selection; no physical mouse input.',
        'One client, real CarNormal trunk, fifteen exact EngineParts IDs, unmodified native action timing.',
        'Frame intervals are UI callback cadence; inclusive Lua wall times use millisecond clock resolution.',
        'Native transfer:update is deliberately unwrapped to preserve ActionQueue provenance; no GPU/FPS claim.']})
