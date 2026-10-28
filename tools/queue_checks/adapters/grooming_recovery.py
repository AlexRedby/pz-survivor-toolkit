"""Exact native singleton-beard full-reset recovery and conservative refusal bank."""
import copy
import json
from pathlib import Path
import re
import shutil

from .. import report
from .tv_controls import MODS, _duration, _number

CASES = ('pending-restore', 'lost-tool', 'active-denied')
PREFIX = '[GROOMING_RECOVERY] '


def definitions():
    checks = {name: {case: dict(effectsVerified=True, serverAuthorityVerified=True) for case in CASES}
              for name in ('success-queued', 'server-authority')}
    return {'grooming-recovery': dict(status='ready', clients=1, default_mods=list(MODS),
        scenario_actions={'singleton-beard-remainder': dict(checks=checks,
            scope='Opt-in ordered grooming_recovery bank. Actual native character-screen Moustache trim, authority LongScruffy baseline and exact favorite already-held root Razor. Full native clear and Java drain in both controls. Pending restore is reset twice again before trim allocation, then completes once with fresh one-shot operation tokens. Authority tool revocation refuses atomically. Started/progressed trim is omitted while an independent untouched reader tail can recover. Three-page native reader blocks pending trim; no duration/lifecycle replacements. Fresh full-selected-pack EN SP/menu Host, one actor. Host native outcomes plus authority effects; no remote callback-count claim.')},
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'], modes=['native', 'toolkit'], languages=['EN']) for case in CASES])}


def validate(selection):
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('grooming_recovery') is not True
            or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Grooming recovery requires its opt-in ordered three-case bank, full selected EN pack, fresh SP/menu Host and one actor')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    # Helpers below are executable verifier inputs, including imported duration
    # and selected-pack parsing; seal them alongside all fixture Lua.
    return [Path(__file__).with_name('tv_controls.py'), Path(__file__).parents[1] / 'mod_selection.py',
            *sorted((root / 'grooming-recovery').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready=PREFIX + 'SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL grooming-recovery'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def _raw(text, marker):
    values = [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]
    if any(type(v) is not dict for v in values):
        raise ValueError('Malformed grooming recovery ' + marker)
    return values


def complete(selection, role, text):
    try:
        return role == 'client1' and _raw(text, 'COMPLETE') == [dict(cases=selection['cases'])]
    except (ValueError, TypeError):
        return False


def _color(value):
    return type(value) is dict and set(value) == {'r', 'g', 'b'} and all(_number(v) and 0 <= v <= 1 for v in value.values())


def _snapshot(value, spec):
    if (type(value) is not dict or set(value) != {'case', 'male', 'items', 'worn', 'hands', 'appearance', 'books'}
            or value['case'] != spec['case'] or value['male'] is not True or type(value['items']) is not list
            or type(value['worn']) is not list or type(value['hands']) is not dict or set(value['hands']) != {'primary', 'secondary'}):
        return False
    ids = []
    for item in value['items']:
        if (type(item) is not dict or set(item) != {'id', 'type', 'container', 'condition', 'favorite', 'count'}
                or type(item['id']) is not int or type(item['type']) is not str or not item['type']
                or type(item['condition']) is not int or item['condition'] < 0 or type(item['favorite']) is not bool
                or type(item['count']) is not int or item['count'] < 1
                or not (item['container'] == 'root' or type(item['container']) is int)):
            return False
        ids.append(item['id'])
    if ids != sorted(set(ids)):
        return False
    parents = {v['id']: v['container'] for v in value['items']}
    for item in ids:
        seen = set()
        while parents[item] != 'root':
            if item in seen or parents[item] not in parents: return False
            seen.add(item); item = parents[item]
    for hand in value['hands'].values():
        if hand is False: continue
        if (type(hand) is not dict or set(hand) != {'id', 'type', 'root', 'sameReference', 'equipParent', 'container'}
                or type(hand['id']) is not int or hand['root'] is not True or hand['sameReference'] is not True
                or hand['equipParent'] is not True or hand['container'] != 'root'
                or not any(v['id'] == hand['id'] and v['type'] == hand['type'] and v['container'] == 'root' for v in value['items'])):
            return False
    if (any(type(v) is not dict or set(v) != {'id', 'location'} or type(v['id']) is not int or v['id'] not in ids
            or type(v['location']) is not str for v in value['worn'])
            or len({v['location'] for v in value['worn']}) != len(value['worn'])):
        return False
    a = value['appearance']
    if (type(a) is not dict or set(a) != {'model', 'nonAttached', 'beardModel', 'color', 'beardColor'}
            or type(a['model']) is not str or type(a['beardModel']) is not str
            or not (a['nonAttached'] is False or type(a['nonAttached']) is str)
            or not _color(a['color']) or not _color(a['beardColor'])):
        return False
    if type(value['books']) is not dict or set(value['books']) != {'front', 'tail'}: return False
    for name, book in value['books'].items():
        s = spec[name]
        if (type(book) is not dict or set(book) != {'id', 'type', 'root', 'total', 'pages', 'characterPages'}
                or book['id'] != s['id'] or type(book['id']) is not int or book['type'] != s['type'] or book['root'] is not True
                or book['total'] != s['total'] or type(book['total']) is not int or type(book['pages']) is not int
                or type(book['characterPages']) is not int or book['pages'] != book['characterPages']
                or not s['initial'] <= book['pages'] <= s['total']
                or not any(v['id'] == s['id'] and v['type'] == s['type'] and v['container'] == 'root' and v['count'] == 1 for v in value['items'])):
            return False
    return True


def expected(spec, enabled):
    result = copy.deepcopy(spec['baseline'])
    if spec['case'] == 'lost-tool':
        result['items'] = [v for v in result['items'] if v['id'] != spec['razor']['id']]
        result['hands']['primary'] = False
    elif enabled:
        if spec['case'] == 'pending-restore':
            result['appearance']['beardModel'] = spec['targetBeard']
            result['books']['front'].update(pages=spec['front']['total'], characterPages=spec['front']['total'])
        result['books']['tail'].update(pages=spec['tail']['total'], characterPages=spec['tail']['total'])
    return result


def _steps(values, roles, spec, restored=False, recancel=False):
    if type(values) is not list or len(values) != len(roles): return False
    tokens = []
    for value, role in zip(values, roles):
        kind = 'ISTrimBeard' if role == 'trim' else 'ISQueueActionsAction' if restored and not (recancel and role == 'front') else 'ISReadABook'
        if (type(value) is not dict or set(value) != {'role', 'type', 'token', 'itemId', 'allocated'}
                or value['role'] != role or value['type'] != kind or type(value['token']) is not int
                or type(value['itemId']) is not int or value['itemId'] != spec['razor' if role == 'trim' else role]['id']
                or type(value['allocated']) is not bool or role == 'trim' and restored and value['allocated'] is not False):
            return False
        tokens.append(value['token'])
    return len(tokens) == len(set(tokens))


def _ack(value, state='started'):
    return (type(value) is dict and set(value) == {'kind', 'transaction', 'token', 'state'}
            and value['kind'] == 'ISTrimBeard' and type(value['transaction']) is int and -128 <= value['transaction'] <= 127
            and value['transaction'] != 0 and value['state'] == state
            and re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(value['token'])) is not None)


def check_case(row, case, selection, prepared, baseline, removed, verified, acks):
    errors = []
    enabled = selection['mode'] == 'toolkit'
    spec = row.get('ids')
    try:
        if (type(spec) is not dict or spec != prepared or spec['case'] != case or spec['mode'] != selection['mode']
                or type(spec['actor']) is not int or spec['initialBeard'] != 'LongScruffy' or spec['targetBeard'] != 'Moustache'
                or type(spec['duration']) is not int or spec['duration'] != 300 or spec['razor']['type'] != 'Base.Razor'
                or type(spec['razor']['id']) is not int): raise ValueError()
        for name, kind, left in [('front', 'Base.BookCarpentry1', 3), ('tail', 'Base.BookCooking1', 1)]:
            s = spec[name]
            if (set(s) != {'id', 'type', 'total', 'initial'} or s['type'] != kind
                    or any(type(s[k]) is not int for k in ('id', 'total', 'initial')) or s['initial'] != s['total'] - left
                    or s['initial'] <= 0): raise ValueError()
        if len({spec[name]['id'] for name in ('razor', 'front', 'tail')}) != 3: raise ValueError()
        seed = spec['baseline']
        if (not _snapshot(seed, spec) or seed['appearance']['beardModel'] != 'LongScruffy'
                or any(seed['books'][name]['pages'] != spec[name]['initial'] for name in ('front', 'tail'))
                or seed['hands']['secondary'] is not False
                or seed['hands']['primary']['id'] != spec['razor']['id']
                or not any(v['id'] == spec['razor']['id'] and v['type'] == 'Base.Razor' and v['container'] == 'root'
                           and v['favorite'] is True and v['count'] == 1 for v in seed['items'])): raise ValueError()
    except (ValueError, KeyError, TypeError):
        return ['Missing exact authority-seeded held razor/appearance/read identities']
    if (row.get('status') != 'passed' or row.get('queueIdle') is not True
            or not _number(row.get('settleMilliseconds')) or row['settleMilliseconds'] < 1000
            or row.get('completionProof') != ('sealed-native-outcome-and-authority-effects' if selection['kind'] == 'mp' else 'native-authority-effects')):
        errors.append('Missing native settling or bounded authority completion proof')
    final = expected(spec, enabled)
    for name, target in [('input', seed), ('authorityBaseline', seed), ('client', final), ('server', final)]:
        if not _snapshot(row.get(name), spec) or row[name] != target: errors.append('Exact grooming resources/pages/hands/appearance differ: ' + name)
    if row.get('authorityBaseline') != baseline or row.get('server') != verified:
        errors.append('Raw independent authority snapshots differ')
    if case == 'lost-tool':
        if row.get('removed') != final or row.get('removed') != removed: errors.append('Exact authority tool revocation missing')
    elif row.get('removed') is not False or removed is not None:
        errors.append('Unexpected authority tool revocation')
    roles = ['trim', 'tail'] if case == 'active-denied' else ['front', 'trim', 'tail']
    admission = row.get('admission', {})
    if (any(admission.get(k) is not True for k in ('singleton', 'alreadyHeld', 'exactRootTool', 'sourceBound'))
            or admission.get('producer') != 'ISCharacterScreen.onTrimBeard' or admission.get('target') != 'Moustache'
            or admission.get('initial') != 'LongScruffy' or type(admission.get('preparationCount')) is not int
            or admission['preparationCount'] != 0 or not _steps(admission.get('queue'), roles[:-1], spec)):
        errors.append('Actual native singleton menu admission differs')
    cancellations, recoveries = row.get('cancellations'), row.get('recoveries')
    count = 3 if enabled and case == 'pending-restore' else 1
    if type(cancellations) is not list or type(recoveries) is not list or len(cancellations) != count or len(recoveries) != count:
        return errors + ['Missing exact ordered reset/restore cycles']
    all_tokens = set(); history_ids = []
    for i, (cancel, recovery) in enumerate(zip(cancellations, recoveries)):
        steps = cancel.get('steps', [])
        if (type(cancel.get('generation')) is not int or cancel['generation'] != i
                or cancel.get('entrypoint') != 'ISTimedActionQueue.clear' or cancel.get('drained') is not True
                or cancel.get('movementStopped') is not True or cancel.get('before') != seed
                or not _steps(steps, roles, spec, i > 0, i > 0) or type(cancel.get('nativeCount')) is not int
                or cancel['nativeCount'] != 1 or not steps or steps[0].get('allocated') is not True
                or any(s.get('allocated') is not False for s in steps[1:])):
            errors.append('Native full reset, singleton grouping or Java drain differs: ' + str(i))
        tokens = [s.get('token') for s in steps]
        old = cancel.get('oldTokens', [])
        if (old != [dict(id=t, cancelled=True) for t in tokens]
                or any(type(t) is not int for t in tokens) or all_tokens.intersection(tokens)):
            errors.append('Cancelled token identity reused or left live')
        all_tokens.update(t for t in tokens if type(t) is int)
        boundary = cancel.get('boundary')
        active = i == 0 and case == 'active-denied'
        delta = boundary.get('delta') if type(boundary) is dict else None
        lower = .02 if active else spec['front']['initial'] / spec['front']['total']
        upper = .5 if active else (spec['front']['initial'] + 1) / spec['front']['total']
        if (type(boundary) is not dict or boundary.get('role') != ('trim' if active else 'front')
                or boundary.get('started') is not True or boundary.get('progress') is not True
                or not _number(delta) or not lower < delta < upper
                or boundary.get('trimUnallocated') is not (not active)):
            errors.append('Native pending/active boundary missing or read checkpoint advanced')
        if active and selection['kind'] == 'mp':
            if not _ack(boundary.get('startedReceipt')): errors.append('Active Host reset lacks sealed native started receipt')
        elif type(boundary) is dict and boundary.get('startedReceipt') is not False:
            errors.append('Unexpected started receipt at reset')
        if not enabled:
            if recovery != dict(available=False, restored=False, historyAbsent=True): errors.append('Queue-off control restored or retained work')
            continue
        expected_count = 1 if case == 'active-denied' else 3
        expected_skipped = 1 if case == 'active-denied' else 0
        if (type(recovery.get('id')) is not int or recovery['id'] <= 0 or recovery['id'] in history_ids
                or type(recovery.get('count')) is not int or recovery['count'] != expected_count
                or type(recovery.get('skipped')) is not int or recovery['skipped'] != expected_skipped
                or recovery.get('reason') != ('started_operation' if case == 'active-denied' else False)
                or recovery.get('previewPure') is not True or recovery.get('staleRejected') is not True
                or type(recovery.get('generation')) is not int or recovery['generation'] != i + 1):
            errors.append('Public recovery eligibility, pure preview or fresh history ID differs')
        history_ids.append(recovery.get('id'))
        if case == 'lost-tool':
            if (recovery.get('available') is not False or recovery.get('restored') is not False
                    or recovery.get('refusedWithoutEffects') is not True or recovery.get('historyAbsent') is not False
                    or recovery.get('steps') is not None): errors.append('Lost-tool recovery did not refuse without effects')
            continue
        new_roles = ['tail'] if case == 'active-denied' else roles
        new_steps = recovery.get('steps', [])
        new_tokens = [s.get('token') for s in new_steps]
        if (recovery.get('available') is not True or recovery.get('restored') is not True
                or recovery.get('historyAbsent') is not True or recovery.get('duplicateRejected') is not True
                or not _steps(new_steps, new_roles, spec, True) or all_tokens.intersection(new_tokens)):
            errors.append('Fresh one-shot public restore changed queue or reused tokens')
        if i + 1 < count:
            following = cancellations[i + 1].get('steps', [])
            identity = lambda steps: [(s.get('role'), s.get('itemId'), s.get('token')) for s in steps]
            if identity(new_steps) != identity(following):
                errors.append('Restored pending queue identity changed before its reset')
        # The next cancellation repeats these exact identities, so add final
        # tokens only once their own cancellation has been checked.
        if i + 1 == count: all_tokens.update(t for t in new_tokens if type(t) is int)
    expected_starts = (['trim:0'] + (['tail:1'] if enabled else []) if case == 'active-denied'
                       else ['front:0'] + (['front:1', 'front:2', 'front:3', 'trim:3', 'tail:3'] if enabled and case == 'pending-restore' else []))
    if row.get('starts') != expected_starts: errors.append('Unexpected native start order or repeated trim')
    commands = row.get('commands', [])
    expected_commands = {(name, 0) for name in roles}
    if enabled and case == 'pending-restore': expected_commands |= {('trim', i) for i in (1, 2, 3)} | {('front', i) for i in (1, 2, 3)} | {('tail', 3)}
    if enabled and case == 'active-denied': expected_commands.add(('tail', 1))
    if (type(commands) is not list or any(type(c) is not dict for c in commands)
            or len(commands) != len(expected_commands) or {(c.get('role'), c.get('generation')) for c in commands} != expected_commands):
        return errors + ['Native admissions missing, duplicated or foreign']
    expected_acks = []
    for command in commands:
        name, gen = command['role'], command['generation']; started = name + ':' + str(gen) in expected_starts
        cancelled = gen == 0 or case == 'pending-restore' and gen < 3
        step_bank = cancellations[gen]['steps'] if gen < len(cancellations) else recoveries[-1].get('steps', [])
        token = next((s['token'] for s in step_bank if s['role'] == name), None)
        if (command.get('type') != ('ISTrimBeard' if name == 'trim' else 'ISReadABook')
                or type(gen) is not int or command.get('itemId') != spec['razor' if name == 'trim' else name]['id']
                or type(command.get('token')) is not int or command['token'] != token
                or command.get('started') is not started or command.get('progress') is not started
                or command.get('cancelled') is not cancelled or command.get('nativeSource') is not True
                or command.get('callbacksIntact') is not True or not _number(command.get('duration'))
                or command['duration'] <= 1 or name == 'trim' and command['duration'] != 300
                or started and not _duration(command)):
            errors.append('Native admission, duration, start/cancel identity differs: ' + name + ':' + str(gen))
        if not started and any(k in command for k in ('allocatedAt', 'effectiveDuration', 'startedAt', 'nativeRef')):
            errors.append('Untouched trim/read allocated before reset')
        if selection['kind'] == 'mp' and name == 'trim' and started:
            state = 'completed' if gen == 3 else 'started'
            ack = command.get('ack')
            if not _ack(ack, state): errors.append('Missing sealed native trim outcome')
            else:
                states = ['started', 'completed'] if state == 'completed' else ['started']
                expected_acks.extend(dict(case=case, generation=gen, kind=ack['kind'], transaction=ack['transaction'], token=ack['token'], state=s) for s in states)
        elif command.get('ack') is not None:
            errors.append('Unexpected native trim receipt')
    if acks != expected_acks: errors.append('Raw native trim receipts missing, duplicated or reordered')
    return errors


def verify(root, selection, catalog):
    root = Path(root); issues, outcomes = [], []
    try:
        validate(selection)
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [r for r in report.events(text) if r.get('suite') == 'grooming-recovery']
        setups = [r for r in events if r.get('event') == 'setup']; rows = [r for r in events if r.get('event') == 'case']
        completed = [r for r in events if r.get('event') == 'complete']
        if (len(setups) != 1 or setups[0].get('cases') != list(CASES) or setups[0].get('nativeDurations') is not True
                or setups[0].get('blocker') != 'native-reader-three-pages' or setups[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
                or len(completed) != 1 or completed[0].get('cases') != list(CASES) or completed[0].get('performed') != 3
                or completed[0].get('failed') != 0 or completed[0].get('skipped') != 0):
            issues.append('Missing exact grooming recovery setup/completion')
        prepared, baselines, final = (_raw(authority, marker) for marker in ('PREPARED', 'BASELINE', 'VERIFIED'))
        removed, acks = _raw(authority, 'REMOVED'), _raw(text, 'ACK')
        if ([r.get('id') for r in rows] != list(CASES)
                or any([r.get('case') for r in values] != list(CASES) for values in (prepared, baselines, final))
                or [r.get('case') for r in removed] != ['lost-tool']):
            issues.append('Raw cases/authority evidence missing, duplicated or reordered')
        for i, case in enumerate(CASES):
            row = rows[i] if i < len(rows) else {}
            errors = check_case(row, case, selection, prepared[i] if i < len(prepared) else None,
                                baselines[i] if i < len(baselines) else None, removed[0] if case == 'lost-tool' and removed else None,
                                final[i] if i < len(final) else None, [a for a in acks if a.get('case') == case])
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('Grooming recovery actor/kind/mode differs')
            issues.extend(case + ': ' + error for error in errors)
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                                 outcome=dict(effectsVerified=not errors, serverAuthorityVerified=not errors)))
        if any(a.get('case') not in CASES for a in acks): issues.append('Unknown-case native trim receipt')
        if not complete(selection, 'client1', text): issues.append('Missing unique grooming recovery completion')
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError) as error:
        issues.append('Grooming recovery verifier ' + type(error).__name__ + ': ' + str(error))
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Programmatic actual native character-screen beard producer and full-clear entrypoint; no physical input/rendering claim.',
        'Three-page native reader is the pending blocker. All actions keep native lifecycle and allocation durations.',
        'One-client fresh macOS full selected pack SP/menu Host; authority effects and sealed native outcomes do not assert remote complete callback counts.']})
