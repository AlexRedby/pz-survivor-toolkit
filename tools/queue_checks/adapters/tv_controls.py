"""Native TV media/control receipts, exact new VHS identity and unrelated book tail."""
import json
import math
import os
from pathlib import Path
import re
import shutil
import zipfile

from .. import report
from .. import preparation_process
from ..placement import validate as validate_placement
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
            'scope': 'Two ordered full-selected-pack SP/menu-Host cases: native UI insertion and optional playback before baseline; eject across a channel setter and redundant pending volume cancellation only with queue enabled. Actual volume/mute/unmute/channel callbacks and two naturally completed root books. Exact new VHS ID/index/type, independent authoritative media/settings/pages and ordered native Host control receipts. Main adjacent TV requires no emitted walk. Optional tv_spatial_controls=true adds a separate Toolkit cold positive decision bank and native walking-success/move-denial prelude in the first case, warm decision timing in both cases, and explicitly not-applicable native-mode controls. No late-loss/failure, physical input, video/audio rendering, arbitrary inventory output capacity or playback-toggle projection coverage implied.'}},
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       modes=['native', 'toolkit'], languages=['EN']) for case in CASES]}}


def validate(selection):
    spatial = selection.get('options', {}).get('tv_spatial_controls', False)
    if type(spatial) is not bool:
        raise ValueError('tv_spatial_controls must be boolean')
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('TV controls require both ordered cases, full selected EN pack, fresh SP/menu Host and one client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted(path for path in (root / 'tv-controls').rglob('*') if path.suffix in ('.lua', '.java')),
            *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            Path(__file__).resolve().parents[1] / 'placement.py']


def _spatial_probe(project, output, game, jdk):
    classes = Path(output) / 'tv-spatial-probe/classes'
    classes.mkdir(parents=True)
    classpath = os.pathsep.join(str(Path(game) / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar'))
    preparation_process.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', classpath, '-d', str(classes),
                            str(Path(project) / 'tests/native_queue/tv-controls/java/Main.java')],
                            check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted(classes.rglob('*.class'))
    if not compiled:
        raise ValueError('TV spatial observation probe compilation produced no classes')
    jar = classes.parent / 'TVSpatialProbe.jar'
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in compiled:
            entry = zipfile.ZipInfo(path.relative_to(classes).as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3;entry.external_attr = 0o100644 << 16;entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, path.read_bytes())
    return jar


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    spatial = selection.get('options', {}).get('tv_spatial_controls', False)
    probe = _spatial_probe(project, output, game, jdk) if spatial else None
    if probe:
        runtime.setdefault('fixture', {}).setdefault('mods', []).append('TVSpatialProbe')
    for role in runtime['roles'].values():
        if probe:
            layer = Path(role['cache']) / 'mods/TVSpatialProbe/42'
            (layer / 'media/java').mkdir(parents=True, exist_ok=True)
            (layer / 'mod.info').write_text('name=Disposable TV spatial observation probe\nid=TVSpatialProbe\nversionMin=42.21\n'
                                          'require=\\ZombieBuddy\njavaPkgName=net.alexredby.tvspatialprobe\n'
                                          'javaJarFile=media/java/TVSpatialProbe.jar\n')
            shutil.copy2(probe, layer / 'media/java/TVSpatialProbe.jar')
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

def _preparation(value, name, target, cancelled):
    expected = dict(name=name, helper='walkAdj', target={key: target[key] for key in ('x', 'y', 'z')},
                    argumentCount=3, keepActions=True, owned=True, constructor=True, resolver=True,
                    sameOperation=True, started=not cancelled, completed=not cancelled, cancelled=cancelled)
    if not cancelled:
        expected.update(children=0, succeeded=True)
    return (isinstance(value, dict) and set(value) == set(expected)
            and isinstance(value.get('target'), dict) and set(value['target']) == {'x', 'y', 'z'}
            and all(type(v) is int for v in value['target'].values())
            and all(type(value[key]) is type(wanted) and value[key] == wanted for key, wanted in expected.items()))


def _timing(value, *, movement=False, cancel_allowed=True, cold=False):
    if (not isinstance(value, dict) or type(value.get('schema')) is not int or value['schema'] != 1
            or value.get('scope') != 'bounded-live-pending-device-entrypoints'
            or value.get('timer') != 'System.nanoTime' or value.get('units') != 'ms'
            or value.get('cacheState') != ('cold-positive' if cold else 'warm-after-positive-bank')
            or value.get('firstUseScope') != ('first-positive-device-query-before-other-policy-probes' if cold
                                             else 'source-cache-warmed-by-cold-positive-bank')
            or value.get('warmSamples') != 3 or type(value.get('queueCount')) is not int or value['queueCount'] < 4
            or any(value.get(key) is not True for key in ('readOnly', 'bindingsUnchanged', 'disabledBeforeEdit'))
            or any(value.get(key) is not False for key in ('completeEditMeasured', 'inputFrameMeasured', 'positiveTimingClaim'))
            or value.get('timerOverhead') != 'included-not-subtracted'):
        return False
    metrics = value.get('metrics')
    if not isinstance(metrics, list) or [r.get('name') for r in metrics if isinstance(r, dict)] != [
            'previewMove', 'evaluateMove', 'previewCancel', 'evaluateCancel']:
        return False
    for metric in metrics:
        if metric.get('decisionKind') != ('advisory' if metric['name'].startswith('preview') else 'authoritative'):
            return False
        first, warm = metric.get('first'), metric.get('warm')
        if not isinstance(first, dict) or not isinstance(warm, list) or len(warm) != 3:
            return False
        expected = not movement if metric['name'].endswith('Move') else cancel_allowed
        for i, sample in enumerate([first, *warm]):
            if (not isinstance(sample, dict) or set(sample) != {'milliseconds', 'allowed', 'reason', 'counts'}
                    or not _number(sample['milliseconds']) or sample['milliseconds'] < 0
                    or sample['allowed'] is not expected or sample['reason'] != first.get('reason')
                    or expected and sample['reason'] is not False):
                return False
            counts = sample['counts']
            if (not isinstance(counts, dict) or set(counts) != {'active', 'gameSourceReads', 'modSourceReads', 'spatialReads', 'apiChecks'}
                    or counts['active'] is not False
                    or any(not _number(counts[k]) or counts[k] < 0 or counts[k] % 1 for k in counts if k != 'active')
                    or i > 0 and (counts['gameSourceReads'] != 0 or counts['modSourceReads'] != 0)):
                return False
            if not movement and counts['spatialReads'] < 1:
                return False
    if cold:
        counts = metrics[0]['first']['counts']
        if counts['gameSourceReads'] < 1 or counts['modSourceReads'] < 1:
            return False
    return True


def _cold_positive(value, ids):
    if (not isinstance(value, dict) or type(value.get('schema')) is not int or value['schema'] != 1
            or value.get('status') != 'performed' or value.get('scope') != 'cold-positive-native-pending-device-decisions'
            or value.get('device') != ids['tv'] or type(value.get('queueBefore')) is not int or value['queueBefore'] != 1
            or type(value.get('queueAfter')) is not int or value['queueAfter'] != 1
            or any(value.get(k) is not True for k in ('queueRestoredToHold', 'sameCurrentNative', 'worldUnchanged', 'cancelledTogether', 'noReplay'))
            or not _timing(value.get('timing'), cold=True)):
        return False
    rows = value.get('commands')
    if not isinstance(rows, list) or [r.get('name') for r in rows] != ['cold-first:approach', 'cold-first', 'cold-last:approach', 'cold-last']:
        return False
    for row in rows:
        prep = ':' in row['name']
        if (row.get('type') != ('ISQueueActionsAction' if prep else 'ISRadioAction')
                or row.get('constructorDuration') != (-1 if prep else 30)
                or any(row.get(k) is not False for k in ('started', 'progress', 'completed'))
                or row.get('cancelled') is not True or type(row.get('starts')) is not int or row['starts'] != 0): return False
        if row.get('preparation') != dict(sameOperation=True, children=False, completed=False): return False
        if not prep and not _close(row.get('value'), .5): return False
    return True


def _spatial_snapshot(value, ids, *, final):
    if (not isinstance(value, dict) or value.get('case') != ids['case'] or value.get('tv') != ids['spatial']['tv']
            or value.get('on') is not True or value.get('powered') is not True
            or not _close(value.get('volume'), .75 if final else .5)
            or not isinstance(value.get('books'), dict) or set(value['books']) != {'hold', 'tail'}):
        return False
    for name, row in value['books'].items():
        seed = ids['spatial'][name]
        if (not isinstance(row, dict) or row.get('id') != seed['id'] or row.get('type') != seed['type']
                or row.get('root') is not True or type(row.get('count')) is not int or row['count'] != 1
                or type(row.get('pages')) is not int or type(row.get('characterPages')) is not int
                or row['pages'] != row['characterPages']):
            return False
        if final:
            if row['pages'] != seed['pages']: return False
        elif name == 'tail':
            if row['pages'] != seed['initial']: return False
        elif not seed['initial'] < row['pages'] < seed['pages']:
            return False
    return True


def _spatial(value, ids, kind):
    try:
        spec = ids['spatial']
        if (not isinstance(spec, dict) or set(spec) != {'tv', 'hold', 'tail'}
                or set(spec['tv']) != {'x', 'y', 'z', 'index'} or any(type(v) is not int for v in spec['tv'].values())
                or spec['tv']['x'] != ids['origin']['x'] - 5
                or any(spec['tv'][key] != ids['origin'][key] for key in ('y', 'z')) or spec['tv']['index'] < 0):
            return False
        for name, item_type in [('hold', 'Base.BookForaging1'), ('tail', 'Base.BookTrapping1')]:
            seed = spec[name]
            if (not isinstance(seed, dict) or seed.get('type') != item_type
                    or any(type(seed.get(k)) is not int for k in ('id', 'pages', 'initial'))
                    or seed['initial'] != seed['pages'] - 2 or seed['initial'] < 0): return False
        if len({spec['hold']['id'], spec['tail']['id'], ids['front']['id'], ids['tail']['id'], ids['tape']['id']}) != 5:
            return False
        if (not isinstance(value, dict) or type(value.get('schema')) is not int or value['schema'] != 1 or value.get('case') != ids['case']
                or value.get('scope') != 'native-walking-success-move-denial-and-legacy-cancel-parity'
                or any(value.get(k) is not True for k in ('returnedToOrigin', 'lifecycleUnchanged', 'queueIdle', 'noReplay'))
                or any(not _number(value.get(k)) or value[k] < 1000 for k in ('settleMilliseconds', 'returnSettleMilliseconds'))
                or value.get('lateLossQualified') is not False
                or value.get('lateLossReason') != 'native-device-validity-does-not-bind-object-liveness'):
            return False
        denied = value.get('denied', {})
        if (not isinstance(denied, dict) or any(denied.get(k) is not True for k in ('move', 'cancelParity', 'queueUnchanged'))
                or denied.get('cancelApplied') is not False or type(denied.get('cancelLegacyAllowed')) is not bool
                or denied.get('cancel') is not (not denied['cancelLegacyAllowed'])):
            return False
        if not _timing(value.get('timing'), movement=True, cancel_allowed=denied['cancelLegacyAllowed']): return False
        if not _cold_positive(value.get('coldPositive'), ids): return False
        if (not _spatial_snapshot(value.get('before'), ids, final=False)
                or not _spatial_snapshot(value.get('client'), ids, final=True)
                or not _spatial_snapshot(value.get('authority'), ids, final=True)
                or value.get('cleanup') != dict(case=ids['case'], tv=spec['tv'], removed=True)):
            return False
        expected = ['hold', 'first:approach', 'first', 'last:approach', 'last', 'tail', 'return']
        rows = value.get('commands')
        if (value.get('order') != expected or not isinstance(rows, list) or [r.get('name') for r in rows] != expected): return False
        by_name = {r['name']: r for r in rows}
        for name, row in by_name.items():
            expected_type = 'ISReadABook' if name in ('hold', 'tail') else 'ISQueueActionsAction' if ':' in name else 'ISWalkToTimedAction' if name == 'return' else 'ISRadioAction'
            duration = row.get('constructorDuration')
            if (row.get('type') != expected_type or row.get('started') is not True or row.get('completed') is not True
                    or type(row.get('starts')) is not int or row['starts'] != 1
                    or not _number(duration) or (duration != -1 if ':' in name or name == 'return' else duration <= 0)
                    or ':' not in name and row.get('progress') is not True): return False
            if name in ('first', 'last') and (duration != 30 or not _close(row.get('value'), .25 if name == 'first' else .75)): return False
            if name in ('hold', 'tail') and row.get('itemId') != spec[name]['id']: return False
        children = value.get('children')
        if not isinstance(children, list) or not 1 <= len(children) <= 32 or not any(r.get('progress') is True for r in children): return False
        for row in children:
            if (row.get('type') != 'ISWalkToTimedAction' or row.get('owner') not in ('first', 'last')
                    or row.get('duration') != -1 or type(row.get('starts')) is not int or row['starts'] != 1 or row.get('started') is not True
                    or row.get('completed') is not True or not isinstance(row.get('destination'), dict)
                    or set(row['destination']) != {'x', 'y', 'z'} or any(type(v) is not int for v in row['destination'].values())): return False
        for name in ('first', 'last'):
            preparation = by_name[name + ':approach'].get('preparation', {})
            count = sum(r['owner'] == name for r in children)
            if (preparation.get('sameOperation') is not True or preparation.get('completed') is not True
                    or type(preparation.get('children')) is not int or preparation['children'] != count
                    or by_name[name].get('preparation') != preparation or name == 'first' and count < 1): return False
        acks = value.get('acks')
        if kind == 'sp': return acks == []
        expected_acks = []
        for name in ('first', 'last'):
            ack = by_name[name].get('ack', {})
            if (ack.get('kind') != 'ISRadioAction' or ack.get('state') != 'completed'
                    or type(ack.get('transaction')) is not int or not -128 <= ack['transaction'] <= 127 or ack['transaction'] == 0
                    or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(ack.get('token')))): return False
            expected_acks.extend(dict(name=name, **{k: ack[k] for k in ('kind', 'transaction', 'token')}, state=state)
                                 for state in ('started', 'completed'))
        return acks == expected_acks and by_name['first']['ack']['token'] != by_name['last']['ack']['token']
    except (KeyError, TypeError, AttributeError):
        return False


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
    try:
        validate_placement(row.get('clientPlacement'), ids.get('origin'), 'local')
        validate_placement(ids.get('placementProof'), ids.get('origin'),
                           'replica' if selection['kind'] == 'mp' else 'local')
        if (ids['tv']['x'] != ids['origin']['x'] - 1
                or any(ids['tv'][key] != ids['origin'][key] for key in ('y', 'z'))):
            raise ValueError('TV offset differs from placement')
    except (ValueError, TypeError, KeyError) as error:
        issues.append('Invalid settled TV placement: ' + str(error))
    if (row.get('status') != 'passed' or row.get('queueIdle') is not True
            or not _number(row.get('settleMilliseconds')) or row['settleMilliseconds'] < 1000):
        issues.append('Missing native completion/idle settling')
    for key, phase in [('input', 'input'), ('baseline', 'baseline'), ('authorityBaseline', 'baseline'), ('client', 'final'), ('server', 'final')]:
        if not _snapshot(row.get(key), ids, case, phase): issues.append('Wrong exact TV/media/books snapshot: ' + key)
    if row.get('authorityBaseline') != authority_baseline or row.get('server') != verified:
        issues.append('Authoritative raw readbacks do not match reported evidence')
    spatial = selection.get('options', {}).get('tv_spatial_controls', False)
    if spatial and mode == 'native':
        if row.get('spatialControl') != dict(status='not-applicable', scope='optional-spatial-prelude-and-decision-timing',
                                           reason='queue-disabled-native-control', movementQualified=False, timingQualified=False, probeInactive=True):
            issues.append('Queue-disabled spatial control must be explicitly not applicable')
        if any(key in row for key in ('spatial', 'timing')) or 'spatial' in ids:
            issues.append('Queue-disabled control acquired spatial gameplay/timing claims')
    elif spatial:
        if 'spatialControl' in row:
            issues.append('Toolkit spatial qualification cannot claim the native not-applicable control')
        if not _timing(row.get('timing')):
            issues.append('Missing bounded read-only pending TV decision timings/counters')
        if case == CASES[0] and not _spatial(row.get('spatial'), ids, selection['kind']):
            issues.append('Missing exact native walking prelude/denial/authority evidence')
        if case != CASES[0] and ('spatial' in row or 'spatial' in ids):
            issues.append('Spatial prelude unexpectedly repeated in the second TV case')
    elif any(key in row for key in ('spatial', 'timing', 'spatialControl')) or 'spatial' in ids:
        issues.append('Unrequested spatial prelude/timing evidence')
    if not issues:
        if not _conserved(row['baseline'], row['client']) or not _conserved(row['authorityBaseline'], verified):
            issues.append('Root inventory changed beyond one exact newly returned VHS')
        if row['client']['outputs'][0]['id'] != verified['outputs'][0]['id']:
            issues.append('Client/server returned VHS ID differs')
    expected = EDITED if mode == 'toolkit' else ORIGINAL
    if row.get('initialQueue') != ORIGINAL or row.get('editedQueue') != expected or row.get('order') != expected:
        issues.append('Native queue, atomic edit or actual start order differs')
    def physical(names):
        return [part for name in names for part in ([name + ':approach', name]
                if mode == 'toolkit' and name in ('volume', 'redundant') else [name])]
    if row.get('initialPhysicalQueue') != physical(ORIGINAL) or row.get('editedPhysicalQueue') != physical(expected):
        issues.append('Exact physical TV preparation/setter queue differs')
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
        scoped = mode == 'toolkit' and name in ('volume', 'redundant')
        if scoped:
            if not _preparation(r.get('preparation'), name, ids['tv'], cancelled):
                issues.append('Exact owned TV approach/zero-child completion differs: ' + str(name))
        elif r.get('preparation') is not None:
            issues.append('Unexpected TV approach dispatcher: ' + str(name))
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
        placements = _raw(text, 'CLIENT_PLACEMENT')
        spatial_verified, spatial_cleaned = (_raw(authority, m) for m in ('SPATIAL_VERIFIED', 'SPATIAL_CLEANED'))
        spatial = selection.get('options', {}).get('tv_spatial_controls', False) and selection['mode'] == 'toolkit'
        if spatial:
            expected_case = [CASES[0]]
            if ([r.get('case') for r in spatial_verified] != expected_case
                    or [r.get('case') for r in spatial_cleaned] != expected_case
                    or not rows or spatial_verified != [rows[0].get('spatial', {}).get('authority')]
                    or spatial_cleaned != [rows[0].get('spatial', {}).get('cleanup')]):
                issues.append('Spatial authority verification/cleanup missing, duplicated or not independently read back')
        elif spatial_verified or spatial_cleaned:
            issues.append('Unrequested spatial authority evidence')
        if [value.get('case') for value in placements] != selection['cases']:
            issues.append('Client TV placement missing, duplicated or out of order')
        if ([r.get('id') for r in rows] != selection['cases'] or any([r.get('case') for r in values] != selection['cases'] for values in (prepared, baseline, verified))):
            issues.append('TV case/authority evidence missing, duplicated or out of order')
        for i, case in enumerate(selection['cases']):
            row = rows[i] if i < len(rows) else {}
            errors = check_case(row, case, selection, prepared[i] if i < len(prepared) else None,
                                baseline[i] if i < len(baseline) else None, verified[i] if i < len(verified) else None,
                                [a for a in acks if a.get('case') == case])
            if i >= len(placements) or placements[i] != {'case': case, 'proof': row.get('clientPlacement')}:
                errors.append('Raw client TV placement differs from case proof')
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('TV actor/kind/mode differs')
            issues += [case + ': ' + e for e in errors]
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors, tailCompleted=not errors, serverAuthorityVerified=not errors,
                             pendingEditsVerified=not errors and selection['mode'] == 'toolkit')))
            if selection.get('options', {}).get('tv_spatial_controls', False):
                if selection['mode'] == 'toolkit':
                    outcomes[-1]['outcome']['boundedDecisionCostCaptured'] = not errors
                    if case == CASES[0]:
                        outcomes[-1]['outcome'].update(nativeSpatialWalkVerified=not errors, coldPositiveDecisionCostCaptured=not errors)
                else:
                    outcomes[-1]['outcome']['spatialControlStatus'] = 'not-applicable'
        if any(a.get('case') not in selection['cases'] for a in acks): issues.append('Unknown-case TV wire receipt')
        if not complete(selection, 'client1', text): issues.append('Missing unique TV completion marker')
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        issues.append('TV verifier ' + type(error).__name__ + ': ' + str(error))
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Native UI callbacks are invoked programmatically; no physical input, audio or video rendering claim.',
        'Adjacent powered TV, exact retail VHS and two native root books in one-client full-pack SP/menu Host.',
        'Optional spatial prelude qualifies real native walking success and existing pending edit permissions; late target-loss and failed/stopped child outcomes remain unqualified.',
        'Optional timings measure bounded read-only public decisions with inactive-after-sample JVM counters; no complete input or frame-cost claim.']}}
