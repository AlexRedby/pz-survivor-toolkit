"""Native full-queue cancellation and one-shot reconstruction of its unspent remainder."""
import json
from pathlib import Path
import re
import shutil

from .. import report
from .tv_controls import MODS, _close, _duration, _ids, _number

CASES = ('movement-cancel', 'clear-queue')
PREFIX = '[QUEUE_RECOVERY] '
ORIGINAL = ['front', 'volume', 'tail']
PHYSICAL = ['front', 'approach', 'volume', 'tail']
STARTS = ['prefix', 'front', 'restoredFront', 'restoredVolume', 'restoredTail']


def definitions():
    checks = {name: {case: {'effectsVerified': True, 'serverAuthorityVerified': True} for case in CASES}
              for name in ('success-queued', 'server-authority')}
    return {'queue-recovery': {'status': 'ready', 'clients': 1, 'default_mods': list(MODS),
        'scenario_actions': {'cancelled-remainder': {'mods': list(MODS), 'checks': checks,
            'scope': 'Two ordered full-selected-pack fresh macOS SP/menu-Host cases: public native StopAllActionQueueWalking and native ISTimedActionQueue.clear. Restore a progressed native skill reader plus untouched TV volume and independent reader once through the public Toolkit recovery API, after actual Java drain. Completed TV prefix never repeats. Queue-off controls retain cancellation with no recovery history. Exact inventory/pages/device identities, unchanged native durations and ordered native Host control receipts. Programmatic entrypoints; no physical-key, mouse or rendering claim.'}},
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                       modes=['native', 'toolkit'], languages=['EN']) for case in CASES]}}


def validate(selection):
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Recovery requires both ordered cases, full selected EN pack, fresh SP/menu Host and one client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [Path(__file__).with_name('tv_controls.py'),
            *sorted((root / 'queue-recovery').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
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
        failure_markers=['[QUEUE_TEST] FAIL queue-recovery'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def _raw(text, marker):
    values = [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]
    if any(not isinstance(v, dict) for v in values):
        raise ValueError('Malformed recovery raw ' + marker)
    return values


def complete(selection, role, text):
    try:
        values = _raw(text, 'COMPLETE')
        return role == 'client1' and len(values) == 1 and values[0].get('cases') == selection['cases']
    except (ValueError, TypeError):
        return False


def _snapshot(value, spec, phase, baseline=None):
    if (not isinstance(value, dict) or value.get('case') != spec['case'] or value.get('tv') != spec['tv']
            or not _ids(value.get('rootIds')) or not _ids(value.get('carriedIds'))
            or not set(value['rootIds']) <= set(value['carriedIds'])):
        return False
    d = value.get('device', {})
    volume = .5 if phase == 'input' else .25 if phase == 'final' and spec['mode'] == 'toolkit' else .4
    if (set(d) != {'on', 'power', 'powerable', 'volume', 'channel', 'hasMedia'}
            or d['on'] is not True or d['powerable'] is not True or d['hasMedia'] is not False
            or type(d['channel']) is not int or d['channel'] != 90000
            or not _number(d['power']) or not 0 < d['power'] <= 1 or not _close(d['volume'], volume)):
        return False
    if set(value.get('books', {})) != {'front', 'tail'}:
        return False
    for name, book in value['books'].items():
        s = spec[name]
        pages = book.get('pages')
        if (book.get('id') != s['id'] or book.get('type') != s['type'] or book.get('root') is not True
                or type(book.get('count')) is not int or book['count'] != 1 or book.get('total') != s['pages']
                or type(pages) is not int or book.get('characterPages') != pages or s['id'] not in value['rootIds']):
            return False
        if phase == 'input' or name == 'tail' and phase == 'baseline':
            if pages != s['initial']: return False
        elif phase == 'baseline':
            if not s['initial'] < pages < s['pages']: return False
        elif spec['mode'] == 'toolkit':
            if pages != s['pages']: return False
        elif not baseline or pages != baseline['books'][name]['pages']:
            return False
    return True


def _steps(value, spec, tokens, enabled, restored=False):
    if (not isinstance(tokens, list) or len(tokens) != 3
            or any(type(token) is not int for token in tokens)):
        return False
    expected = []
    target = {key: spec['tv'][key] for key in ('x', 'y', 'z')}
    for name in PHYSICAL if enabled else ORIGINAL:
        group = 0 if name == 'front' else 2 if name == 'tail' else 1
        kind = ('ISQueueActionsAction' if name == 'approach' or restored and name in ('front', 'tail')
                else 'ISRadioAction' if name == 'volume' else 'ISReadABook')
        expected.append(dict(name=name, type=kind, token=tokens[group],
                             approach=dict(owned=True, helper='walkAdj', target=target) if name == 'approach' else False))
    if not isinstance(value, list) or len(value) != len(expected):
        return False
    for step in value:
        if (not isinstance(step, dict) or set(step) != {'name', 'type', 'token', 'approach'}
                or type(step['token']) is not int):
            return False
        proof = step['approach']
        if step['name'] == 'approach':
            if (not isinstance(proof, dict) or proof.get('owned') is not True
                    or not isinstance(proof.get('target'), dict)
                    or any(type(coordinate) is not int for coordinate in proof['target'].values())):
                return False
        elif proof is not False:
            return False
    return value == expected


def _projection_ui(value, tokens):
    if (not isinstance(value, dict) or not isinstance(tokens, list) or len(tokens) != 3
            or any(type(token) is not int for token in tokens)
            or any(value.get(key) is not True for key in
                   ('nativeUI', 'nativeSnapshot', 'stableReuse', 'actionsUnchanged', 'expansionRestored',
                    'hiddenCleared', 'reopened', 'visibilityRestored'))
            or type(value.get('queueCount')) is not int or value['queueCount'] != 4
            or type(value.get('groups')) is not int or value['groups'] != 3
            or type(value.get('operation')) is not int or value['operation'] != tokens[1]):
        return False
    collapsed = [(1, False, 1, 1, 1, 1), (2, True, 2, 3, 2, 3), (4, False, 4, 4, 4, 4)]
    expanded = collapsed[:2] + [(2, False, 2, 2, 2, 3), (3, False, 3, 3, 2, 3)] + collapsed[2:]
    for name, specs in (('collapsed', collapsed), ('expanded', expanded), ('reopenedView', collapsed)):
        sample = value.get(name)
        if (not isinstance(sample, dict) or sample.get('stableRows') is not True
                or type(sample.get('currentIndex')) is not int or sample['currentIndex'] != 1
                or not isinstance(sample.get('rows'), list) or len(sample['rows']) != len(specs)):
            return False
        for row, (index, header, first, last, group_first, group_last) in zip(sample['rows'], specs):
            expected = dict(actionIndex=index, header=header, first=first, last=last,
                            groupFirst=group_first, groupLast=group_last,
                            token=tokens[0 if index == 1 else 2 if index == 4 else 1])
            if (not isinstance(row, dict) or row != expected or type(row.get('header')) is not bool
                    or any(type(row.get(key)) is not int for key in expected if key != 'header')):
                return False
    return True


def check_case(row, case, selection, prepared, authority_baseline, verified, acks):
    errors = []
    spec = row.get('ids')
    try:
        if (not isinstance(spec, dict) or spec != prepared or spec['case'] != case or spec['mode'] != selection['mode']
                or set(spec['tv']) != {'x', 'y', 'z', 'index'} or any(type(v) is not int for v in spec['tv'].values())
                or spec['tv']['index'] < 0 or set(spec['origin']) != {'x', 'y', 'z'}
                or any(type(v) is not int for v in spec['origin'].values())
                or spec['tv']['x'] != spec['origin']['x'] - 1 or spec['tv']['y'] != spec['origin']['y'] or spec['tv']['z'] != spec['origin']['z']):
            raise ValueError()
        for name, kind, left in [('front', 'Base.BookCarpentry1', 3), ('tail', 'Base.BookCooking1', 2)]:
            s = spec[name]
            if (s['type'] != kind or any(type(s[k]) is not int for k in ('id', 'pages', 'initial'))
                    or s['initial'] != s['pages'] - left or s['initial'] < 0): raise ValueError()
        if spec['front']['id'] == spec['tail']['id']: raise ValueError()
    except (KeyError, ValueError, TypeError):
        return ['Missing exact authoritative recovery identities']
    enabled = selection['mode'] == 'toolkit'
    if (row.get('status') != 'passed' or row.get('queueIdle') is not True
            or not _number(row.get('settleMilliseconds')) or row['settleMilliseconds'] < 1000):
        errors.append('Missing native idle settling')
    for key, phase in [('input', 'input'), ('baseline', 'baseline'), ('authorityBaseline', 'baseline'), ('client', 'final'), ('server', 'final')]:
        if not _snapshot(row.get(key), spec, phase, row.get('authorityBaseline') if key == 'server' else row.get('baseline')):
            errors.append('Wrong exact recovery snapshot: ' + key)
    if row.get('authorityBaseline') != authority_baseline or row.get('server') != verified:
        errors.append('Independent raw authority readbacks differ')
    if not errors:
        for key in ('rootIds', 'carriedIds'):
            if any(row[name][key] != row['input'][key] for name in ('baseline', 'authorityBaseline', 'client', 'server')):
                errors.append('Exact item conservation differs')
    wishlist = row.get('wishlist', {})
    try:
        for name in ('empty', 'collapsed'):
            sample = wishlist[name]
            if (not _number(sample['elapsedMs']) or not 1500 <= sample['elapsedMs'] < 10000
                    or type(sample['draws']) is not int or sample['draws'] < 10
                    or any(type(sample[key]) is not int or sample[key] != 0
                           for key in ('carriedCalls', 'rowClears', 'selectorClears'))):
                raise ValueError()
        expanded = wishlist['expanded']
        if (expanded['amount'] != 7 or type(expanded['carried']) is not int or expanded['carried'] < 1
                or expanded['firstDrawFresh'] is not True
                or any(wishlist[key] is not True for key in ('reopened', 'removed', 'restored'))):
            raise ValueError()
    except (KeyError, ValueError, TypeError):
        errors.append('Wishlist native idle/expand/cleanup workload evidence differs')
    cancellation, recovery = row.get('cancellation', {}), row.get('recovery', {})
    entrypoint = 'IsoGameCharacter.StopAllActionQueueWalking' if case == 'movement-cancel' else 'ISTimedActionQueue.clear'
    if (cancellation.get('entrypoint') != entrypoint or cancellation.get('initialQueue') != (PHYSICAL if enabled else ORIGINAL)
            or cancellation.get('drained') is not True or cancellation.get('movementStopped') is not True
            or type(cancellation.get('nativeCount')) is not int or cancellation['nativeCount'] != 1
            or not _snapshot(cancellation.get('before'), spec, 'baseline')):
        errors.append('Native cancellation, saved progress or Java drain evidence differs')
    old = cancellation.get('oldTokens', [])
    if (len(old) != 3 or any(type(r.get('id')) is not int or r.get('cancelled') is not True for r in old)
            or len({r.get('id') for r in old}) != 3):
        errors.append('Original operation tokens were not distinctly cancelled')
    if not _steps(cancellation.get('steps'), spec, [r.get('id') for r in old], enabled):
        errors.append('Original physical actions or exact preparation operation differ')
    if enabled:
        if not _projection_ui(cancellation.get('projectionUI'), [r.get('id') for r in old]):
            errors.append('Original production queue projection UI evidence differs')
        if not _projection_ui(recovery.get('projectionUI'), recovery.get('tokens')):
            errors.append('Restored production queue projection UI evidence differs')
        workload = recovery.get('previewWorkload', {})
        if (not _number(workload.get('elapsedMs')) or not 1500 <= workload['elapsedMs'] < 10000
                or type(workload.get('previews')) is not int or workload['previews'] < 4
                or (type(workload.get('plans')) is not int or workload['plans'] != 0)
                or workload.get('nativeUI') is not True):
            errors.append('Idle recovery UI reconstructed actions or lacks native observations')
        tokens = recovery.get('tokens')
        if (type(recovery.get('id')) is not int or recovery['id'] < 1 or recovery.get('count') != 3
                or type(recovery.get('count')) is not int or type(recovery.get('skipped')) is not int or recovery['skipped'] != 0
                or recovery.get('available') is not True or recovery.get('restored') is not True or recovery.get('previewPure') is not True
                or recovery.get('duplicateRejected') is not True or recovery.get('historyAbsent') is not True
                or not isinstance(tokens, list) or not all(type(token) is int for token in tokens)):
            errors.append('Missing one-shot public recovery evidence')
        if (not isinstance(tokens, list) or len(tokens) != 3 or len(set(tokens)) != 3
                or set(tokens) & {r.get('id') for r in old} or row.get('restoredQueue') != PHYSICAL
                or not _steps(recovery.get('steps'), spec, tokens, True, restored=True)):
            errors.append('Recovery reused tokens or changed remainder order')
    elif (recovery.get('available') is not False or recovery.get('restored') is not False or recovery.get('historyAbsent') is not True
          or row.get('restoredQueue') != []):
        errors.append('Queue-off control recovered work or retained history')
    expected_starts = STARTS if enabled else STARTS[:2]
    if row.get('order') != expected_starts:
        errors.append('Completed prefix repeated or observed action order differs')
    commands = row.get('commands', [])
    expected_names = ['prefix', 'front', 'volume', 'tail'] + (STARTS[2:] if enabled else [])
    names = [r.get('name') for r in commands]
    if names[:4] != expected_names[:4] or sorted(names[4:]) != sorted(expected_names[4:]):
        errors.append('Missing, duplicate or foreign native action')
    native_acks = []
    prefix_token = commands[0].get('token') if commands else None
    if type(prefix_token) is not int or prefix_token in {r.get('id') for r in old}:
        errors.append('Paid prefix lacks its own original identity')
    if enabled and prefix_token in recovery.get('tokens', []):
        errors.append('Recovery reused the paid prefix token')
    for command in commands:
        name = command.get('name'); book = name in ('front', 'tail', 'restoredFront', 'restoredTail')
        cancelled = name in ORIGINAL
        did_start = name in expected_starts
        if (command.get('type') != ('ISReadABook' if book else 'ISRadioAction')
                or command.get('mode') != ('' if book else 'SetVolume')
                or command.get('producer') != ('native ISReadABook constructor' if book else 'recovery native ISRadioAction constructor' if name == 'restoredVolume' else 'native RWM callback')
                or command.get('cancelled') is not cancelled or command.get('started') is not did_start
                or command.get('progress') is not did_start or not _number(command.get('duration')) or command['duration'] <= 1
                or not book and command['duration'] != 30):
            errors.append('Native producer/start/cancellation differs: ' + str(name))
        if name in ORIGINAL and command.get('token') != (old[ORIGINAL.index(name)].get('id') if len(old) == 3 else None):
            errors.append('Original native action token differs')
        if did_start and not _duration(command): errors.append('Native allocation duration differs: ' + str(name))
        if book:
            s = spec['front' if name in ('front', 'restoredFront') else 'tail']
            initial = row.get('baseline', {}).get('books', {}).get('front', {}).get('pages') if name == 'restoredFront' else s['initial']
            if command.get('itemId') != s['id'] or command.get('initialPages') != initial:
                errors.append('Native read identity/checkpoint differs: ' + str(name))
        if enabled and name in STARTS[2:] and command.get('token') != recovery.get('tokens', [None]*3)[STARTS[2:].index(name)]:
            errors.append('Real restored native action has wrong fresh token')
        if selection['kind'] == 'mp' and not book and did_start:
            ack = command.get('ack', {})
            if (ack.get('kind') != 'ISRadioAction' or ack.get('state') != 'completed'
                    or type(ack.get('transaction')) is not int or not -128 <= ack['transaction'] <= 127 or ack['transaction'] == 0
                    or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(ack.get('token')))):
                errors.append('Missing completed native Host transaction: ' + str(name))
            else: native_acks.append((name, ack))
        elif command.get('ack') is not None:
            errors.append('Unstarted/native-book/SP action has unexpected receipt')
    expected_acks = [dict(case=case, name=name, **{k: ack[k] for k in ('kind', 'transaction', 'token')}, state=state)
                     for name, ack in native_acks for state in ('started', 'completed')]
    if acks != expected_acks or len({ack['token'] for _, ack in native_acks}) != len(native_acks):
        errors.append('Raw native Host receipts missing, duplicated, reused or reordered')
    return errors


def verify(root, selection, catalog):
    root = Path(root); issues, outcomes = [], []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [r for r in report.events(text) if r.get('suite') == 'queue-recovery']
        setups = [r for r in events if r.get('event') == 'setup']; rows = [r for r in events if r.get('event') == 'case']
        completed = [r for r in events if r.get('event') == 'complete']
        if (len(setups) != 1 or setups[0].get('cases') != list(CASES) or setups[0].get('nativeDurations') is not True
                or setups[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
                or len(completed) != 1 or completed[0].get('cases') != list(CASES) or completed[0].get('performed') != 2
                or completed[0].get('failed') != 0 or completed[0].get('skipped') != 0):
            issues.append('Missing exact recovery setup/completion gate')
        prepared, baseline, verified = (_raw(authority, marker) for marker in ('PREPARED', 'BASELINE', 'VERIFIED'))
        acks = _raw(text, 'ACK')
        if ([r.get('id') for r in rows] != list(CASES)
                or any([r.get('case') for r in values] != list(CASES) for values in (prepared, baseline, verified))):
            issues.append('Case/authority evidence missing, duplicated or out of order')
        for i, case in enumerate(CASES):
            row = rows[i] if i < len(rows) else {}
            errors = check_case(row, case, selection, prepared[i] if i < len(prepared) else None,
                                baseline[i] if i < len(baseline) else None, verified[i] if i < len(verified) else None,
                                [a for a in acks if a.get('case') == case])
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('Recovery actor/kind/mode differs')
            issues += [case + ': ' + error for error in errors]
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                                 outcome=dict(effectsVerified=not errors, serverAuthorityVerified=not errors, tailCompleted=not errors and selection['mode']=='toolkit')))
        if any(a.get('case') not in CASES for a in acks): issues.append('Unknown-case native receipt')
        if not complete(selection, 'client1', text): issues.append('Missing unique recovery completion marker')
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError) as error:
        issues.append('Recovery verifier ' + type(error).__name__ + ': ' + str(error))
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Programmatic native movement-stop/full-clear entrypoints; no physical keyboard/mouse or rendering claim.',
        'Idle recovery preview observes natural UI callbacks without replacing action lifecycles; Wishlist uses public requests, native collapse/title-hover callbacks and first-post-draw freshness. Operation counts are not CPU/FPS timing or large-inventory native stress; no second-player revocation coverage is implied.',
        'Fresh one-client selected-pack macOS SP/menu Host, adjacent powered TV, root skill books only.']})
