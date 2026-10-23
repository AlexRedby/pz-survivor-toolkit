"""Native TV media/control receipts, exact new VHS identity and unrelated book tail."""
import json
import math
from pathlib import Path
import re
import shutil

from .. import report
from ..mod_selection import metadata, mod_ids

PROJECT = Path(__file__).resolve().parents[3]
MODS = mod_ids(metadata(PROJECT / 'SurvivorQoL-selected.ini')['Mods'])
CASES = ('eject-idle', 'eject-playing')
PREFIX = '[TV_CONTROLS] '
ORIGINAL = ['front', 'volume', 'redundant', 'mute', 'unmute', 'channel', 'eject', 'tail']
EDITED = ['front', 'volume', 'mute', 'unmute', 'eject', 'channel', 'tail']
MODES = {'insert': '', 'play': 'TogglePlayMedia', 'front': '', 'volume': 'SetVolume',
         'redundant': 'SetVolume', 'mute': 'MuteVolume', 'unmute': 'UnMuteVolume',
         'channel': 'SetChannel', 'eject': '', 'tail': ''}


def definitions():
    checks = {name: {case: {'effectsVerified': True, 'tailCompleted': True,
                            'serverAuthorityVerified': True} for case in CASES}
              for name in ('success-queued', 'server-authority')}
    for name in ('move-independent', 'cancel-waiting'):
        checks[name] = {case: {'effectsVerified': True, 'pendingEditsVerified': True} for case in CASES}
    return {'tv-controls': {'status': 'ready', 'clients': 1, 'default_mods': list(MODS),
        'scenario_actions': {'tv-eject-controls': {'mods': list(MODS), 'checks': checks,
            'scope': 'Two ordered full-selected-pack SP/menu-Host cases: native UI insertion and optional playback before baseline; eject across a channel setter and redundant pending volume cancellation only with queue enabled. Actual volume/mute/unmute/channel callbacks and two naturally completed root books. Exact new VHS ID/index/type, independent authoritative media/settings/pages and ordered native Host control receipts. Adjacent TV requires no emitted walk; no physical input, video/audio rendering, arbitrary inventory output capacity or playback-toggle projection coverage implied.'}},
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       modes=['native', 'toolkit'], languages=['EN']) for case in CASES]}}


def validate(selection):
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('TV controls require both ordered cases, full selected EN pack, fresh SP/menu Host and one client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'tv-controls').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL tv-controls'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    if role != 'client1':
        return False
    try:
        values = _raw(text, 'COMPLETE')
        return len(values) == 1 and values[0].get('cases') == selection['cases']
    except (ValueError, TypeError):
        return False


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _close(value, expected):
    return _number(value) and _number(expected) and abs(value - expected) < .0001


def _ids(value):
    return (isinstance(value, list) and all(type(v) is int for v in value)
            and len(set(value)) == len(value) and sorted(value) == value)


def _snapshot(value, ids, case, phase):
    if not isinstance(value, dict) or value.get('case') != case or value.get('tv') != ids['tv']:
        return False
    if (not _ids(value.get('rootIds')) or not _ids(value.get('carriedIds'))
            or not set(value['rootIds']) <= set(value['carriedIds'])):
        return False
    if type(value.get('originalCount')) is not int or value.get('originalCount') != (1 if phase == 'input' else 0):
        return False
    d = value.get('device', {})
    expected = dict(on=True, powerable=True, volume=.25 if phase == 'final' else .5,
                    channel=95000 if phase == 'final' else 90000, micMuted=False,
                    hasMedia=phase == 'baseline', mediaIndex=ids['tape']['index'] if phase == 'baseline' else -1,
                    mediaType=1, playing=phase == 'baseline' and case == 'eject-playing')
    if not isinstance(d, dict) or set(d) != {*expected, 'power'} or not _number(d['power']) or not 0 < d['power'] <= 1:
        return False
    for key, wanted in expected.items():
        if key == 'volume':
            if not _close(d[key], wanted): return False
        elif type(d[key]) is not type(wanted) or d[key] != wanted:
            return False
    books = value.get('books', {})
    if not isinstance(books, dict) or set(books) != {'front', 'tail'}:
        return False
    for name, row in books.items():
        spec = ids[name]
        pages = spec['pages'] if phase == 'final' else spec['initial']
        if (not isinstance(row, dict) or row.get('id') != spec['id'] or row.get('type') != spec['type']
                or row.get('root') is not True or type(row.get('count')) is not int or row['count'] != 1
                or row.get('total') != spec['pages'] or row.get('pages') != pages or row.get('characterPages') != pages
                or spec['id'] not in value['rootIds']):
            return False
    outputs = value.get('outputs')
    if not isinstance(outputs, list) or len(outputs) != (1 if phase == 'final' else 0):
        return False
    if phase == 'input':
        return ids['tape']['id'] in value['rootIds']
    if ids['tape']['id'] in value['rootIds']:
        return False
    if phase == 'final':
        o, tape = outputs[0], ids['tape']
        return (isinstance(o, dict) and type(o.get('id')) is int and o['id'] != tape['id'] and o['id'] in value['rootIds']
                and o.get('type') == tape['type'] and o.get('index') == tape['index'] and o.get('mediaType') == 1
                and o.get('root') is True and o.get('recorded') is True and type(o.get('count')) is int and o['count'] == 1)
    return True


def _conserved(before, after):
    return (set(after['rootIds']) - set(before['rootIds']) == {after['outputs'][0]['id']}
            and set(before['rootIds']) <= set(after['rootIds'])
            and set(after['carriedIds']) - set(before['carriedIds']) == {after['outputs'][0]['id']}
            and set(before['carriedIds']) <= set(after['carriedIds']))



def _duration(row):
    fields = ('duration', 'effectiveDuration', 'nativeDurationBefore', 'nativeDurationAfter',
              'durationSampleBefore', 'durationSampleAfter', 'allocatedAt', 'startedAt')
    if (any(not _number(row.get(key)) for key in fields)
            or type(row.get('durationSamples')) is not int or row['durationSamples'] < 1):
        return False
    before, after, effective = row['nativeDurationBefore'], row['nativeDurationAfter'], row['effectiveDuration']
    return (min(before, after, effective) > 1 and row['durationSampleBefore'] <= row['durationSampleAfter']
            and row['durationSampleAfter'] == row['allocatedAt'] <= row['startedAt']
            and abs(after - before) <= max(.001, row['duration'] * .00001)
            and min(before, after) - .001 <= effective <= max(before, after) + .001)

def check_case(row, case, selection, prepared, authority_baseline, verified, acks):
    issues = []
    mode = selection['mode']
    ids = row.get('ids')
    try:
        if (not isinstance(ids, dict) or ids != prepared or ids['case'] != case or ids['mode'] != mode
                or set(ids['tv']) != {'x', 'y', 'z', 'index'} or any(type(v) is not int for v in ids['tv'].values())
                or ids['tv']['index'] < 0 or ids['tape']['type'] != 'Base.VHS_Retail'
                or type(ids['tape']['id']) is not int or type(ids['tape']['index']) is not int or ids['tape']['index'] < 0
                or ids['tape']['mediaType'] != 1 or ids['front']['type'] != 'Base.BookCarpentry1'
                or ids['tail']['type'] != 'Base.BookCooking1'
                or len({ids['tape']['id'], ids['front']['id'], ids['tail']['id']}) != 3):
            raise ValueError('fixture identities differ')
        for name in ('front', 'tail'):
            if any(type(ids[name][k]) is not int for k in ('id', 'pages', 'initial')) or ids[name]['initial'] != ids[name]['pages'] - 2:
                raise ValueError('native book seed differs')
    except (KeyError, TypeError, ValueError):
        return ['Missing exact authoritative TV/item identities']
    if (row.get('status') != 'passed' or row.get('queueIdle') is not True
            or not _number(row.get('settleMilliseconds')) or row['settleMilliseconds'] < 1000):
        issues.append('Missing native completion/idle settling')
    for key, phase in [('input', 'input'), ('baseline', 'baseline'), ('authorityBaseline', 'baseline'), ('client', 'final'), ('server', 'final')]:
        if not _snapshot(row.get(key), ids, case, phase): issues.append('Wrong exact TV/media/books snapshot: ' + key)
    if row.get('authorityBaseline') != authority_baseline or row.get('server') != verified:
        issues.append('Authoritative raw readbacks do not match reported evidence')
    if not issues:
        if not _conserved(row['baseline'], row['client']) or not _conserved(row['authorityBaseline'], verified):
            issues.append('Root inventory changed beyond one exact newly returned VHS')
        if row['client']['outputs'][0]['id'] != verified['outputs'][0]['id']:
            issues.append('Client/server returned VHS ID differs')
    expected = EDITED if mode == 'toolkit' else ORIGINAL
    if row.get('initialQueue') != ORIGINAL or row.get('editedQueue') != expected or row.get('order') != expected:
        issues.append('Native queue, atomic edit or actual start order differs')
    edit = row.get('edit', {})
    if (not isinstance(edit, dict) or edit.get('reordered') is not (mode == 'toolkit')
            or edit.get('cancelled') != (['redundant'] if mode == 'toolkit' else [])
            or edit.get('untouched') is not True or edit.get('atomic') is not True):
        issues.append('Missing pure independent move/cancel evidence')
    setup_names = ['insert', 'play'] if case == 'eject-playing' else ['insert']
    rows = row.get('setup', []) + row.get('commands', [])
    if ([r.get('name') for r in row.get('setup', [])] != setup_names
            or [r.get('name') for r in row.get('commands', [])] != ORIGINAL):
        issues.append('Missing exact native UI/book commands')
    expected_ack_rows = []
    for r in rows:
        name = r.get('name'); book = name in ('front', 'tail'); cancelled = name == 'redundant' and mode == 'toolkit'
        kind = 'ISReadABook' if book else 'ISDeviceMediaAction' if name in ('insert', 'eject') else 'ISRadioAction'
        if (r.get('type') != kind or r.get('mode') != MODES.get(name) or r.get('producer') != ('native ISReadABook constructor' if book else 'native RWM callback')
                or r.get('cancelled') is not cancelled or r.get('started') is not (not cancelled) or r.get('progress') is not (not cancelled)
                or not _number(r.get('duration')) or r['duration'] <= 0 or not book and r['duration'] != 30):
            issues.append('Native command/cancellation differs: ' + str(name)); continue
        if cancelled:
            if r.get('ack') is not None: issues.append('Cancelled setter received a native transaction')
            continue
        if not _duration(r):
            issues.append('Native duration/start evidence differs: ' + str(name))
        if name == 'eject' and (r.get('mediaAtStart') != ids['tape']['index'] or r.get('playingAtStart') is not (case == 'eject-playing')):
            issues.append('Eject did not observe the intended native playback state')
        if selection['kind'] == 'mp' and not book:
            ack = r.get('ack', {})
            if (not isinstance(ack, dict) or ack.get('kind') != kind or ack.get('state') != 'completed'
                    or type(ack.get('transaction')) is not int or not -128 <= ack['transaction'] <= 127 or ack['transaction'] == 0
                    or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(ack.get('token')))):
                issues.append('Missing exact completed native Host transaction: ' + name)
            else:
                expected_ack_rows.append((name, ack))
        elif r.get('ack') is not None:
            issues.append('Unexpected control transaction in SP/book command')
    if selection['kind'] == 'mp':
        by_name = dict(expected_ack_rows)
        names = setup_names + [n for n in expected if n not in ('front', 'tail')]
        raw_expected = [dict(case=case, name=n, **{k: by_name[n][k] for k in ('kind', 'transaction', 'token')}, state=state)
                        for n in names if n in by_name for state in ('started', 'completed')]
        if acks != raw_expected or len({a['token'] for _, a in expected_ack_rows}) != len(expected_ack_rows):
            issues.append('Raw native Host receipts missing, duplicated, reused or out of execution order')
    elif acks:
        issues.append('SP has unexpected wire receipts')
    return issues


def _raw(text, marker):
    values = [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]
    if any(not isinstance(v, dict) for v in values): raise ValueError('Malformed TV raw ' + marker)
    return values


def verify(root, selection, catalog):
    root = Path(root);issues, outcomes = [], []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [r for r in report.events(text) if r.get('suite') == 'tv-controls']
        rows = [r for r in events if r.get('event') == 'case']
        setups = [r for r in events if r.get('event') == 'setup']
        completions = [r for r in events if r.get('event') == 'complete']
        if (len(setups) != 1 or setups[0].get('cases') != selection['cases']
                or setups[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
                or setups[0].get('nativeDurations') is not True
                or len(completions) != 1 or completions[0].get('cases') != selection['cases']
                or completions[0].get('performed') != len(selection['cases'])
                or completions[0].get('failed') != 0 or completions[0].get('skipped') != 0):
            issues.append('Missing exact TV setup/completion gate')
        prepared, baseline, verified = (_raw(authority, m) for m in ('PREPARED', 'BASELINE', 'VERIFIED'))
        acks = _raw(text, 'ACK')
        if ([r.get('id') for r in rows] != selection['cases'] or any([r.get('case') for r in values] != selection['cases'] for values in (prepared, baseline, verified))):
            issues.append('TV case/authority evidence missing, duplicated or out of order')
        for i, case in enumerate(selection['cases']):
            row = rows[i] if i < len(rows) else {}
            errors = check_case(row, case, selection, prepared[i] if i < len(prepared) else None,
                                baseline[i] if i < len(baseline) else None, verified[i] if i < len(verified) else None,
                                [a for a in acks if a.get('case') == case])
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('TV actor/kind/mode differs')
            issues += [case + ': ' + e for e in errors]
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors, tailCompleted=not errors, serverAuthorityVerified=not errors,
                             pendingEditsVerified=not errors and selection['mode'] == 'toolkit')))
        if any(a.get('case') not in selection['cases'] for a in acks): issues.append('Unknown-case TV wire receipt')
        if not complete(selection, 'client1', text): issues.append('Missing unique TV completion marker')
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        issues.append('TV verifier ' + type(error).__name__ + ': ' + str(error))
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Native UI callbacks are invoked programmatically; no physical input, audio or video rendering claim.',
        'Adjacent powered TV, exact retail VHS and two native root books in one-client full-pack SP/menu Host.']}}
