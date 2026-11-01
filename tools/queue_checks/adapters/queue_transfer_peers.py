"""Two real menu-Host clients: physical ownership and advisory transfer evidence."""
import math
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

from .. import receipts
from .book_controls import _stop_probe
from .tv_controls import MODS

CASES = ('disjoint-returns', 'shared-capacity', 'contested-pickup', 'lost-done')
ROLES = ('client1', 'client2')
PREFIX = '[QUEUE_PEERS] '
LIMITS = [
    'Two real EN/RU macOS clients in a fresh menu Host with the full selected pack; no dedicated-server, WAN or Windows qualification.',
    'Contested pickup preserves native preparation-failure behavior; its losing actor does not qualify generic independent-tail isolation.',
    'Lost Done drops one exact native acknowledgement while independent container replication runs; unknown outcome never grants return, Keep or replay authority.',
]


def definitions():
    checks = {name: {case: dict(effectsVerified=True, serverAuthorityVerified=True) for case in CASES}
              for name in ('success-queued', 'server-authority')}
    return {'queue-transfer-peers': dict(status='ready', clients=2, default_mods=list(MODS),
        scenario_actions={'peer-transfers': dict(checks=checks,
            scope='Ordered selectable two-client menu-Host bank: disjoint borrowed returns, shared destination admission, contested pickup and exact lost-Done unknown outcome. Native book producers, original durations, physical server ownership, unique item IDs and actor-bound advisory receipts; no replay or permission expansion.')},
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['mp'],
                    modes=['native', 'toolkit'], languages=['EN', 'RU']) for case in CASES])}


def validate(selection):
    cases = selection.get('cases')
    if (not isinstance(cases, list) or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') != 'mp' or selection.get('mode') not in ('native', 'toolkit')
            or type(selection.get('clients')) is not int or selection['clients'] != 2
            or selection.get('languages') != ['EN', 'RU'] or selection.get('mods') != MODS
            or selection.get('options', {}).get('mp_host') is not True
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Queue transfer peers require an ordered nonempty case subset, two EN/RU clients, full selected pack and fresh menu Host')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    code = Path(project) / 'PZSurvivorToolkit/42/media/lua'
    return [Path(__file__).with_name('tv_controls.py'), Path(__file__).with_name('book_controls.py'),
            Path(project) / 'tests/test_queue_transfer_peers.py',
            *sorted(path for path in (root / 'queue-transfer-peers').rglob('*') if path.suffix in ('.lua', '.java')),
            *sorted((root / 'startup').rglob('*.lua')), root / 'health/shared/QueueHealthEvents.lua',
            root / 'support/QueueEnergyPlacement.lua', code / 'client/PZSurvivorToolkit/ActionQueueTransferRequests.lua',
            root / 'book-controls/java/Main.java', code / 'client/PZSurvivorToolkit/ActionQueueSettlement.lua']


def _probe(project, output, game, jdk):
    classes = Path(output) / 'queue-peers-probe/classes'
    classes.mkdir(parents=True)
    inputs = sorted((Path(project) / 'tests/native_queue/queue-transfer-peers/java').rglob('*.java'))
    if not inputs:
        raise ValueError('Queue peer probe Java sources missing')
    classpath = os.pathsep.join(str(Path(game) / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar'))
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', classpath, '-d', str(classes),
                    *map(str, inputs)], check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted(classes.rglob('*.class'))
    if not compiled:
        raise ValueError('Queue peer probe compilation produced no classes')
    jar = classes.parent / 'QueuePeersProbe.jar'
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in compiled:
            archive.write(path, path.relative_to(classes).as_posix())
    return jar


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    probe = _probe(project, output, game, jdk)
    stop = _stop_probe(project, output, game, jdk)
    runtime.setdefault('fixture', {}).setdefault('mods', []).extend(['QueuePeersProbe', 'BookControlsStopProbe'])
    for role in runtime['roles'].values():
        layer = Path(role['cache']) / 'mods/QueuePeersProbe/42'
        (layer / 'media/java').mkdir(parents=True, exist_ok=True)
        (layer / 'mod.info').write_text('name=Disposable queue peer reply probe\nid=QueuePeersProbe\nversionMin=42.21\n'
                                      'require=\\ZombieBuddy\njavaPkgName=net.alexredby.queuepeersprobe\n'
                                      'javaJarFile=media/java/QueuePeersProbe.jar\n')
        shutil.copy2(probe, layer / 'media/java/QueuePeersProbe.jar')
        passive = Path(role['cache']) / 'mods/BookControlsStopProbe/42'
        (passive / 'media/java').mkdir(parents=True, exist_ok=True)
        (passive / 'mod.info').write_text('name=Disposable native transfer stop observation\nid=BookControlsStopProbe\nversionMin=42.21\n'
                                        'require=\\ZombieBuddy\njavaPkgName=net.alexredby.bookcontrolsprobe\n'
                                        'javaJarFile=media/java/BookControlsStopProbe.jar\n')
        shutil.copy2(stop, passive / 'media/java/BookControlsStopProbe.jar')
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for path in sorted((root / 'startup').rglob('*.lua')):
            target = lua / path.relative_to(root / 'startup')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        for path in (root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua'):
            target = lua / 'shared' / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    runtime['fixture'].update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL queue-transfer-peers'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def raw(text, event):
    return receipts.records(text, PREFIX, event)


def _integer(value, minimum=None):
    return type(value) is int and (minimum is None or value >= minimum)


def _number(value):
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


def _ids(value):
    return isinstance(value, list) and all(_integer(x, 1) for x in value) and sorted(set(value)) == value


def _transaction(value):
    return _integer(value) and -128 <= value <= 127 and value != 0


def _finish(selection):
    return dict(cases=selection['cases'], performed=len(selection['cases']), failed=0, restored=True)


def complete(selection, role, text):
    try:
        rows = raw(text, 'COMPLETE')
        return (role in ('server', *ROLES) and rows == [_finish(selection)]
                and type(rows[0].get('performed')) is int and type(rows[0].get('failed')) is int
                and rows[0].get('restored') is True)
    except (ValueError, TypeError, KeyError):
        return False


def _same_case(value, case, token, index):
    return (isinstance(value, dict) and value.get('case') == case and value.get('token') == token
            and type(value.get('index')) is int and value['index'] == index)


def _seed_errors(seed, case, index):
    errors = []
    if (not isinstance(seed, dict) or seed.get('case') != case or seed.get('index') != index
            or type(seed.get('index')) is not int or not isinstance(seed.get('token'), str) or not seed['token']):
        return ['Missing exact server seed/case token/index']
    actors = seed.get('actors')
    if (not isinstance(actors, list) or len(actors) != 2
            or [a.get('role') for a in actors if isinstance(a, dict)] != list(ROLES)
            or any(not _integer(a.get('onlineId'), 0) for a in actors)
            or len({a['onlineId'] for a in actors}) != 2):
        return ['Missing two distinct authoritative native actors']
    for actor in actors:
        for name in ('front', 'tail'):
            book = actor.get(name)
            if (not isinstance(book, dict) or not _integer(book.get('id'), 1)
                    or not isinstance(book.get('ft'), str) or not book['ft']
                    or not _integer(book.get('initial'), 0) or not _integer(book.get('total'), 1)
                    or book['initial'] >= book['total']):
                errors.append('Invalid authoritative ' + name + ' book identity/pages')
    if errors:
        return errors
    fronts = [a['front']['id'] for a in actors]
    tails = [a['tail']['id'] for a in actors]
    if (len(set(tails)) != 2 or set(fronts) & set(tails)
            or (fronts[0] == fronts[1]) is not (case == 'contested-pickup')):
        errors.append('Fixture front/tail IDs overlap outside the contested item')
    items = seed.get('items')
    if (not isinstance(items, list) or len(items) != len(set(fronts + tails))
            or any(not isinstance(item, dict) for item in items)
            or {item.get('id') for item in items} != set(fronts + tails)
            or any(not isinstance(item.get('initialEndpoint'), str) for item in items)):
        errors.append('Authoritative seed item set differs from exact fixture books')
    else:
        for actor in actors:
            for name in ('front', 'tail'):
                book = actor[name]
                item = next(item for item in items if item['id'] == book['id'])
                endpoint = actor['role'] + '-root' if name == 'tail' else ('source1' if case in ('contested-pickup', 'shared-capacity') else 'source' + actor['role'][-1])
                if item.get('ft') != book['ft'] or item.get('initialEndpoint') != endpoint:
                    errors.append('Seed item type or initial physical endpoint differs')
    originals = seed.get('originalRootIds')
    if (not isinstance(originals, dict) or set(originals) != set(ROLES)
            or any(not _ids(originals[role]) for role in ROLES)
            or set(originals.get('client1', [])) & set(originals.get('client2', []))
            or any(set(originals.get(role, [])) & set(fronts + tails) for role in ROLES)):
        errors.append('Original root inventory identities are missing or overlap fixture items')
    stores = seed.get('stores')
    if (not isinstance(stores, list) or len(stores) != 2 or [s.get('key') for s in stores if isinstance(s, dict)] != ['source1', 'source2']
            or any(any(not _integer(s.get(key)) for key in ('x', 'y', 'z', 'index'))
                   or not _number(s.get('capacity')) or s['capacity'] <= 0 for s in stores)
            or len({(s['x'], s['y'], s['z'], s['index']) for s in stores}) != 2):
        errors.append('Exact distinct authority stores/capacities missing')
    return errors


def _observation_errors(value, record, sample, book, enabled):
    if value is False:
        return []
    if not enabled or not isinstance(value, dict):
        return ['Foreign/native-mode private request observation']
    if (set(value) - {'id', 'fullType', 'transaction', 'phase', 'boundary', 'sourceExact', 'paired', 'currentHandle',
                      'nativeHandle', 'wireAmbiguous', 'ambiguous'}
            or any(type(v) not in (str, int, float, bool) for v in value.values())
            or value.get('id') != book['id'] or value.get('fullType') != book['ft']
            or value.get('phase') not in ('before', 'submitted', 'failed')
            or value.get('boundary') not in ('start', 'continuation')
            or any(type(value.get(k)) is not bool for k in ('sourceExact', 'paired', 'currentHandle', 'nativeHandle', 'wireAmbiguous'))
            or 'ambiguous' in value and type(value['ambiguous']) is not bool):
        return ['Advisory receipt differs from its exact action/item/transaction']
    tx = value.get('transaction')
    if tx is not None and tx != 0:
        if (not _transaction(tx) or tx != record.get('transaction')
                or sample.get('transaction') != tx and not (sample.get('point') in ('perform-finish', 'terminal') and sample.get('transaction') == 0)):
            return ['Advisory transaction differs from current/historical native cursor']
    if value.get('currentHandle') and (not value.get('nativeHandle') or value.get('wireAmbiguous')
                                      or value.get('ambiguous') or not _transaction(tx)):
        return ['Ambiguous advisory receipt claimed a current native handle']
    return []


def _instant(record):
    """A native zero-time return can perform between ticks without a start sample."""
    return (record.get('role') == 'return' and record.get('duration') == 0
            and record.get('started') is False and record.get('progress') is False
            and isinstance(record.get('nativeRef'), str) and bool(record['nativeRef'])
            and {'perform-begin', 'perform-finish'} <= {s.get('point') for s in record.get('samples', [])}
            and any(f.get('phase') == 'perform' and f.get('succeeded') is True for f in record.get('finishes', [])))


def _record_errors(row, actor, enabled):
    errors = []
    records = row.get('records')
    if (not isinstance(records, list) or len(records) < 4 or any(not isinstance(r, dict) for r in records)
            or [r.get('role') for r in records[:3]] != ['pickup', 'front', 'return']
            or sum(r.get('role') == 'tail' for r in records) != 1
            or any(r.get('role') not in ('return', 'tail') for r in records[3:])):
        return ['Missing exact core pickup/front/return and independent tail records']
    sequences = [r.get('sequence') for r in records]
    refs = [r.get('actionRef') for r in records]
    native_refs = [r.get('nativeRef') for r in records if r.get('started') is True or _instant(r)]
    if (not all(_integer(x, 1) for x in sequences) or sorted(set(sequences)) != sequences
            or any(not isinstance(x, str) or not x for x in refs) or len(set(refs)) != len(records)
            or len(set(native_refs)) != len(native_refs)):
        errors.append('Native action sequences/references duplicated or missing')
    for record in records:
        role = record['role']; book = actor['tail' if role == 'tail' else 'front']
        instant = record is not records[2] and _instant(record)
        # Stock ISInventoryTransferAction.new sets both maxTime and the queued
        # item time to -1 on MP clients: the server acknowledgement ends it.
        # This is a native pending sentinel, not a negative elapsed duration.
        duration = record.get('duration')
        valid_duration = (_number(duration) and
            (duration == -1 or duration == 0 and instant if role in ('pickup', 'return') else duration > 0))
        if (record.get('item') != book['id'] or type(record.get('started')) is not bool
                or type(record.get('progress')) is not bool or record['progress'] and not record['started']
                or not valid_duration
                or (not _integer(record.get('token'), 1) if enabled else record.get('token') is not False and not _integer(record.get('token'), 1))
                or (not isinstance(record.get('nativeRef'), str) or not record['nativeRef'] if record['started'] or instant else record.get('nativeRef') is not False)):
            errors.append('Native ' + role + ' identity/start/duration/operation evidence differs')
        samples, finishes = record.get('samples'), record.get('finishes')
        if not isinstance(samples, list) or not isinstance(finishes, list):
            errors.append('Missing native sample/finish records'); continue
        times = []
        for sample in samples:
            if (not isinstance(sample, dict) or sample.get('point') not in ('pending', 'started', 'perform-begin', 'perform-finish', 'terminal')
                    or not _number(sample.get('at')) or sample['at'] < 0
                    or type(sample.get('done')) is not bool or type(sample.get('rejected')) is not bool
                    or sample.get('transaction') is not False and not _integer(sample.get('transaction'))):
                errors.append('Malformed native transfer boundary sample'); continue
            times.append(sample['at'])
            errors.extend(_observation_errors(sample.get('observation'), record, sample, book, enabled))
        if times != sorted(times):
            errors.append('Native samples reordered')
        for finish in finishes:
            if (not isinstance(finish, dict) or finish.get('phase') not in ('perform', 'complete', 'stop')
                    or not _number(finish.get('at')) or type(finish.get('succeeded')) is not bool):
                errors.append('Malformed native completion callback')
        if (not record.get('started') and not instant and (record.get('progress') or finishes or record.get('nativeRef') is not False)
                or sum(f.get('phase') == 'perform' for f in finishes) > 1):
            errors.append('Unstarted/duplicate native callback acquired authority')
    if enabled and len({r.get('token') for r in records[:3]}) != 1:
        errors.append('Borrowed pickup/read/return operation token differs')
    return errors


def _succeeded(record):
    return (record.get('started') is True or _instant(record)) and any(f.get('phase') in ('perform', 'complete')
        and f.get('succeeded') is True for f in record.get('finishes', []))


def _transfer_done(record):
    return (_succeeded(record) and _transaction(record.get('transaction'))
            and any(s.get('transaction') == record['transaction'] and s.get('done') is True
                    and s.get('rejected') is False for s in record.get('samples', [])))


def _pairing_errors(record):
    """Pairing proves one attempt only; physical success is checked separately."""
    anchored = paired = False; submitted = None; errors = []
    for sample in record.get('samples', []):
        value = sample.get('observation')
        if not isinstance(value, dict):
            continue
        if value.get('phase') == 'submitted':
            binding = tuple(value.get(k) for k in ('boundary', 'sourceExact', 'id', 'fullType', 'nativeHandle', 'ambiguous', 'transaction'))
            if submitted is not None and submitted != binding:
                errors.append('Singleton advisory submitted binding changed')
            submitted = binding
        exact = (value.get('phase') == 'submitted' and value.get('sourceExact') is True
                 and value.get('nativeHandle') is True and value.get('wireAmbiguous') is False
                 and value.get('ambiguous') is False and _transaction(value.get('transaction')))
        if exact and value.get('currentHandle') is True and value.get('paired') is False:
            anchored = True
        if value.get('paired') is True:
            rejected_stop = (sample.get('point') == 'terminal'
                and isinstance(record.get('nativeStopEntry'), dict) and record['nativeStopEntry'].get('rejected') is True)
            if (not exact or not anchored or not paired and sample.get('point') != 'perform-finish' and not rejected_stop):
                errors.append('Advisory attempt pairing lacks prior exact handle or actual attempt boundary')
            paired = True
        elif paired:
            errors.append('Singleton advisory paired state reverted')
    if _transfer_done(record) and not (anchored and paired):
        errors.append('Successful owned return lacks exact native request anchor and attempt pairing')
    return errors


def _stopped_errors(record, actor, rejected, enabled):
    entry, returned = record.get('nativeStopEntry'), record.get('nativeStopReturned')
    if not isinstance(entry, dict) or not isinstance(returned, dict):
        return ['Missing native stop entry/returned before transaction removal']
    if (entry.get('actor') != actor['onlineId'] or entry.get('item') != actor['front']['id']
            or not _transaction(entry.get('transaction')) or entry.get('transaction') != record.get('transaction')
            or entry.get('nativeRef') != record.get('nativeRef') or not entry.get('nativeRef')
            or entry.get('done') is not False or entry.get('rejected') is not rejected
            or entry.get('current') is not True or entry.get('endpointsExact') is not True
            or not _number(entry.get('at')) or returned.get('transaction') != (
                0 if enabled and rejected and record.get('role') == 'return' else entry.get('transaction'))
            or not _number(returned.get('at')) or returned['at'] < entry['at']
            or returned.get('sameNative') is not True or returned.get('returned') is not True):
        return ['Native stop lost exact actor/item/live transaction identity or pending/rejected state']
    return _observation_errors(entry.get('observation'), record, entry, actor['front'], enabled)


def _unknown_errors(value, row, actor, enabled, applied):
    errors = []
    if not isinstance(value, dict):
        return ['Missing genuine pending unknown-outcome boundary']
    probe = value.get('probe'); after = value.get('afterProbe'); record = row['records'][2]
    if not isinstance(probe, dict) or not isinstance(after, dict):
        return ['Missing source-bound before/after reply-loss probe']
    expected = dict(sourceExact=True, historyFromConnectionStart=True, armed=True, bound=True, used=True,
                    droppedDone=1, droppedAccept=0, droppedReject=0, passedAccept=1, passedReject=0,
                    attempts=1, requestCount=1, reused=0, nativePresent=True, pendingExact=True,
                    nativeState='Accept', transaction=record.get('transaction'), item=actor['front']['id'], actor=actor['onlineId'],
                    failure='', closed='', fault='drop-only-native-Done-no-replay')
    if (any(type(probe.get(k)) is not type(v) or probe[k] != v for k, v in expected.items())
            or not _transaction(probe.get('transaction'))):
        errors.append('Reply loss is not one exact fresh pending native request')
    if value.get('done') is not False or value.get('rejected') is not False or value.get('cleared') is not True:
        errors.append('Unknown native transaction was terminal, missing, or not explicitly cleared')
    private = value.get('privateState')
    if enabled:
        if (not isinstance(private, dict) or private.get('phase') != 'submitted' or private.get('sourceExact') is not True
                or private.get('currentHandle') is not True or private.get('nativeHandle') is not True
                or private.get('paired') is not False or private.get('wireAmbiguous') is not False or private.get('ambiguous') is not False
                or private.get('transaction') != probe.get('transaction') or private.get('id') != actor['front']['id']
                or private.get('fullType') != actor['front']['ft']):
            errors.append('Unknown advisory observation borrowed another owner or fabricated completion pairing')
    elif private is not False:
        errors.append('Queue-off unknown outcome invented a private owner')
    if (any(after.get(k) != probe.get(k) or type(after.get(k)) is not type(probe.get(k))
            for k in ('sourceExact', 'historyFromConnectionStart', 'droppedDone', 'droppedAccept', 'droppedReject',
                      'attempts', 'requestCount', 'reused', 'transaction', 'item', 'actor', 'fault'))
            or after.get('nativePresent') is not False or after.get('pendingExact') is not False):
        errors.append('Unknown clear/recovery replayed or retained the native transaction')
    recovery = value.get('recovery')
    if recovery is not False and (not enabled or not isinstance(recovery, dict)
            or not _integer(recovery.get('count'), 0) or not _integer(recovery.get('skipped'), 1)
            or not isinstance(recovery.get('reason'), str) or not recovery['reason']):
        errors.append('Unknown recovery did not explicitly skip unsafe replay')
    if _succeeded(record) or row.get('keptIds') != []:
        errors.append('Pending unknown return fabricated success or Keep authority')
    errors.extend(_stopped_errors(record, actor, False, enabled))
    if not isinstance(applied, dict):
        errors.append('Missing independent server physical return before native clear')
    return errors


def check_case(seed, result, clients, selection, case, index, release, capacity=None, applied=None):
    errors = _seed_errors(seed, case, index)
    if errors:
        return errors
    token = seed['token']; enabled = selection['mode'] == 'toolkit'
    if not _same_case(release, case, token, index):
        errors.append('Missing exact shared release after both actors resolve')
    if (not _same_case(result, case, token, index) or result.get('originalsPreserved') is not True
            or result.get('clients') != clients):
        errors.append('Server result lost original inventory or exact client DTO copies')
    if case == 'shared-capacity':
        if (not _same_case(capacity, case, token, index) or capacity.get('capacity') != 1
                or capacity.get('roomBefore') is not True or capacity.get('combinedFits') is not False
                or capacity.get('items') != [a['front']['id'] for a in seed['actors']]):
            errors.append('Missing authoritative shared capacity intervention after both readers progress')
    elif capacity is not None:
        errors.append('Foreign shared-capacity intervention')
    final = result.get('items', [])
    if (not isinstance(final, list) or len(final) != len(seed['items'])
            or any(not isinstance(item, dict) for item in final)
            or sorted(item.get('id', -1) for item in final) != sorted(item['id'] for item in seed['items'])):
        return errors + ['Missing, duplicated or foreign authoritative physical items']
    by_id = {item['id']: item for item in final}
    for item in seed['items']:
        actual = by_id[item['id']]
        if actual.get('ft') != item['ft'] or type(actual.get('count')) is not int or actual['count'] != 1:
            errors.append('Authoritative item identity/type/count differs')
    losers = []
    for actor in seed['actors']:
        role = actor['role']; row = clients.get(role)
        if (not _same_case(row, case, token, index) or row.get('role') != role or row.get('onlineId') != actor['onlineId']
                or type(row.get('onlineId')) is not int or row.get('mode') != selection['mode']
                or row.get('queueEnabled') is not enabled or row.get('sourceBound') is not True or row.get('queueIdle') is not True):
            errors.append(role + ': exact actor/mode/source/idle identity differs'); continue
        local = _record_errors(row, actor, enabled)
        if local:
            errors.extend(role + ': ' + e for e in local); continue
        pickup, front, returning = row['records'][:3]
        tail = next(record for record in row['records'] if record['role'] == 'tail')
        if enabled:
            for transfer in (r for r in row['records'] if r['role'] == 'return'):
                errors.extend(role + ': ' + error for error in _pairing_errors(transfer))
        front_item, tail_item = by_id[actor['front']['id']], by_id[actor['tail']['id']]
        lost = case == 'lost-done' and role == 'client1'
        loser = case == 'shared-capacity' and front_item.get('endpoint') == role + '-root' or case == 'contested-pickup' and not front.get('progress')
        if loser:
            losers.append(role)
        expected_front = actor['front']['initial'] if case == 'contested-pickup' and loser else actor['front']['total']
        expected_tail = actor['tail']['initial'] if lost or loser and (case == 'contested-pickup' or not enabled) else actor['tail']['total']
        if (row.get('frontPages') != expected_front or row.get('tailPages') != expected_tail
                or row.get('tailInitial') != actor['tail']['initial'] or row.get('tailTotal') != actor['tail']['total']
                or tail_item.get('pages') != expected_tail or tail_item.get('endpoint') != role + '-root'):
            errors.append(role + ': exact reader/tail progress or physical tail differs')
        if not loser or case != 'contested-pickup':
            if not _transfer_done(pickup) or not _succeeded(front) or not front.get('progress'):
                errors.append(role + ': borrowed front lacks native successful pickup/read')
        elif (front.get('started') or _succeeded(pickup) or _succeeded(returning)
              or any(s.get('observation') is not False for r in (pickup, returning) for s in r['samples'])):
            errors.append(role + ': rejected pickup earned foreign cleanup/return authority')
        if expected_tail == actor['tail']['total'] and not _succeeded(tail):
            errors.append(role + ': independent tail completion callback missing')
        if lost:
            errors.extend(_unknown_errors(row.get('unknown'), row, actor, enabled, applied))
        elif row.get('unknown') is not False:
            errors.append(role + ': unexpected unknown-outcome claim')
        if not lost and not loser and not _transfer_done(returning):
            errors.append(role + ': native successful return acknowledgement missing')
        if loser:
            rejected_record = pickup if case == 'contested-pickup' else returning
            errors.extend(role + ': ' + e for e in _stopped_errors(rejected_record, actor, True, enabled))
            if _succeeded(rejected_record):
                errors.append(role + ': native rejected transfer claimed successful completion')
        for extra in row['records'][3:]:
            if extra['role'] != 'return':
                continue
            if lost or case != 'shared-capacity' or not loser or _transfer_done(extra):
                errors.append(role + ': unexpected or successful supplemental native return')
            elif extra.get('started'):
                errors.extend(role + ': supplemental return: ' + e for e in _stopped_errors(extra, actor, True, enabled))
            elif _instant(extra) and (enabled or extra.get('transaction') != 0
                    or any(s.get('observation') is not False for s in extra.get('samples', []))):
                errors.append(role + ': instantaneous native fallback acquired request/private authority')
        kept, blocked = row.get('keptIds'), row.get('blocked')
        if not isinstance(blocked, list) or not _ids(kept):
            errors.append(role + ': malformed blocked/Keep evidence')
        elif case == 'shared-capacity' and loser and enabled:
            if (kept != [actor['front']['id']] or len(blocked) != 1
                    or blocked[0].get('itemId') != actor['front']['id'] or not _integer(blocked[0].get('id'), 1)
                    or blocked[0].get('state') != 'blocked' or not isinstance(blocked[0].get('reason'), str) or not blocked[0]['reason']):
                errors.append(role + ': lost capacity did not preserve exact blocked return and Keep entry')
        elif kept or blocked:
            errors.append(role + ': unrelated actor/case acquired blocked return or Keep authority')
        endpoint = role + '-root' if loser and case == 'shared-capacity' else 'source1' if case in ('shared-capacity', 'contested-pickup') else 'source' + role[-1]
        if front_item.get('endpoint') != endpoint:
            errors.append(role + ': authoritative front endpoint differs')
        if front_item.get('pages') != actor['front']['total']:
            errors.append(role + ': authoritative front pages were not completed by the real reader')
    if case in ('shared-capacity', 'contested-pickup') and len(losers) != 1:
        errors.append('Peer race did not produce exactly one physical/native loser')
    if case == 'lost-done':
        if not _same_case(applied, case, token, index):
            errors.append('Missing exact authority applied boundary')
        else:
            observed = [item for item in applied.get('items', []) if item.get('id') == seed['actors'][0]['front']['id']]
            if len(observed) != 1 or observed[0] != by_id[seed['actors'][0]['front']['id']] or observed[0].get('endpoint') != 'source1':
                errors.append('Unknown return was not physically applied before local native clear')
    capacities = result.get('capacity')
    if (not isinstance(capacities, dict) or set(capacities) != {'source1', 'source2'}
            or any(not isinstance(value, dict) or not _number(value.get('weight')) or not _number(value.get('capacity'))
                   or not 0 <= value['weight'] <= value['capacity'] for value in capacities.values())
            or case == 'shared-capacity' and capacities.get('source1', {}).get('capacity') != 1):
        errors.append('Authority final container capacity exceeded or unverified')
    return errors


def verify(root, selection, catalog):
    root = Path(root); issues = []; case_errors = {case: [] for case in selection['cases']}
    try:
        validate(selection)
        texts = {role: (root / (role + '-launch.log')).read_text(errors='replace') for role in ('server', *ROLES)}
        if texts['server'].count('[STARTUP_TEST] SERVER_READY') != 1:
            issues.append('Missing unique real Host server readiness')
        for role, text in texts.items():
            if not complete(selection, role, text):
                issues.append(role + ': missing complete restored ordered bank')
            if '[QUEUE_TEST] FAIL ' in text:
                issues.append(role + ': native fixture failed')
        events = {role: {event: raw(text, event) for event in ('SEED', 'RELEASE', 'CAPACITY', 'APPLIED', 'RESULT', 'CASE')}
                  for role, text in texts.items()}
        server = events['server']
        if server['CASE'] or any(events[role][event] for role in ROLES
                                 for event in ('SEED', 'RELEASE', 'CAPACITY', 'APPLIED', 'RESULT')):
            issues.append('Authority/client receipt published by the wrong native role')
        for event in ('SEED', 'RELEASE', 'RESULT'):
            if [v.get('case') for v in server[event]] != selection['cases']:
                issues.append('Server ' + event + ' missing, duplicated or reordered')
        for event, expected in [('CAPACITY', [c for c in selection['cases'] if c == 'shared-capacity']),
                                ('APPLIED', [c for c in selection['cases'] if c == 'lost-done'])]:
            if [v.get('case') for v in server[event]] != expected:
                issues.append('Server ' + event + ' missing, duplicated or foreign')
        tokens = [r.get('token') for r in server['SEED']]
        if len(set(tokens)) != len(tokens):
            issues.append('Server case tokens reused')
        lifecycle = []
        for line in texts['server'].splitlines():
            for event in ('SEED', 'RELEASE', 'CAPACITY', 'APPLIED', 'RESULT'):
                marker = PREFIX + event + ' '
                if marker in line:
                    lifecycle.append((event, receipts.decode_object(line.split(marker, 1)[1]).get('case')))
        expected_lifecycle = [(event, case) for case in selection['cases']
            for event in (['SEED', 'RELEASE'] + (['CAPACITY'] if case == 'shared-capacity' else [])
                          + (['APPLIED'] if case == 'lost-done' else []) + ['RESULT'])]
        if lifecycle != expected_lifecycle:
            issues.append('Authority cases overlapped or lifecycle boundaries were reordered')
        for role in ROLES:
            if [v.get('case') for v in events[role]['CASE']] != selection['cases']:
                issues.append(role + ': case DTOs missing, duplicated or reordered')
            for marker in ('[QUEUE_TEST] PREFLIGHT_COMPLETE mods=' + str(len(selection['mods'])) + ' mode=' + selection['mode'],
                           '[QUEUE_TEST] NATIVE_CONNECTED'):
                if texts[role].count(marker) != 1:
                    issues.append(role + ': missing unique native readiness')
        for index, case in enumerate(selection['cases'], 1):
            def one(role, event):
                values = [v for v in events[role][event] if v.get('case') == case]
                return values[0] if len(values) == 1 else None
            clients = {role: one(role, 'CASE') for role in ROLES}
            case_errors[case] = check_case(one('server', 'SEED'), one('server', 'RESULT'), clients, selection,
                case, index, one('server', 'RELEASE'), one('server', 'CAPACITY'), one('server', 'APPLIED'))
        for role, text in texts.items():
            complete_at = text.find(PREFIX + 'COMPLETE ')
            if any(text.rfind(PREFIX + event + ' ') > complete_at for event in events[role]):
                issues.append(role + ': evidence published after restoration completion')
    except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError) as error:
        issues.append('Queue transfer peers verifier ' + type(error).__name__ + ': ' + str(error))
    global_errors = list(issues)
    issues.extend(case + ': ' + error for case, errors in case_errors.items() for error in errors)
    outcomes = [dict(actor=role, case=case, status='failed' if global_errors or case_errors[case] else 'passed',
                     reason='; '.join(global_errors + case_errors[case]),
                     outcome=dict(effectsVerified=not (global_errors or case_errors[case]),
                                  serverAuthorityVerified=not (global_errors or case_errors[case])))
                for role in ROLES for case in selection['cases']]
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': LIMITS})
