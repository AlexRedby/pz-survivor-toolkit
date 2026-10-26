"""Exact native preparation effects and cancellation cleanup; uses the common runner."""
import json
import re
import shutil
from pathlib import Path
from .. import report
from .tv_controls import MODS, _number

BASE_CASES = ['mask-after-removal', 'p4-after-pickup', 'p4-keep-return']
ALL_CASES = [*BASE_CASES, 'p4-editor-off', 'p4-editor-reenabled']
CASES = ALL_CASES
PREFIX = '[QUEUE_CLEANUP] '


def base_case(case):
    return {'p4-editor-off': 'p4-after-pickup',
            'p4-editor-reenabled': 'p4-after-pickup'}.get(case, case)


def definitions():
    return {'cleanup-cancel': {'status': 'ready', 'clients': 1, 'default_mods': list(MODS),
        'scenario_actions': {'earned-native-cleanup': {'mods': list(MODS),
            'scope': 'Current full selected pack, disposable macOS SP/menu Host. Real BulkFood/native eat mask removal and native onLiteratureItems borrowed First Aid book pickup/read/allowMissing return. Mask public per-operation cancellation and real Panel programmatic header press/release after confirmed preparation preserve exact cleanup before an independent reader; real expanded-child return press/release keeps the earned borrowed item carried, continues its full native read and prevents late return through native/P4 idle; original P4 hands/activation restore retains native idle-session timing and is required at final idle. Editor-off variants disable ModOptions immediately after accepted group cancel while cleanup drains; reenabled variant turns it back on while the exact earned return is current. Queue-off controls execute unchanged producers to natural native/P4 completion. Exact item/container, worn/hands, food portion/paid borrowed pages, native lifecycle, editor transitions and authority evidence; programmatic native entrypoints and real Panel hit-tested press/release, no physical input.',
            'checks': {'server-authority': {case: {'authoritative': True, 'cleanupRestored': True, 'tailCompleted': True} for case in CASES},
                       'cancel-active': {case: {'cancelled': True, 'cleanupBeforeTail': True} for case in CASES}},
            'toolkit_only': ['cancel-active']}},
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'], modes=['native', 'toolkit'], languages=['EN']) for case in CASES]}}


def validate(selection):
    chosen = selection.get('cases')
    if (not isinstance(chosen, list) or not chosen or chosen != [case for case in CASES if case in chosen] or selection.get('mods') != MODS or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Cleanup cancellation requires a nonempty canonical ordered case subset, current selected pack, fresh SP/menu Host and one EN client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    code = Path(project) / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit'
    return [Path(__file__).with_name('tv_controls.py'), code / 'ActionQueuePanel.lua', code / 'ActionQueueTidyIntent.lua',
            *sorted((root / 'cleanup-cancel').rglob('*.lua')),
            *sorted((root / 'startup').rglob('*.lua')), root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL cleanup-cancel'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def raw(text, marker):
    return [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]


def complete(selection, role, text):
    try:
        rows = raw(text, 'COMPLETE')
        return role == 'client1' and len(rows) == 1 and rows[0] == {'cases': selection['cases']}
    except (ValueError, TypeError):
        return False


def owned_cleanup_before_tail(snapshot, ids, keep=False):
    return snapshot.get('maskWorn') is True if base_case(ids['case']) == BASE_CASES[0] else snapshot.get('borrowedContainer') == ('root' if keep else 'bag')


def restored(snapshot, ids, keep=False):
    if base_case(ids['case']) == BASE_CASES[0]:
        return owned_cleanup_before_tail(snapshot, ids)
    return (owned_cleanup_before_tail(snapshot, ids, keep) and snapshot.get('primary') == ids['items']['torch']
            and snapshot.get('secondary') == ids['items']['secondary'] and snapshot.get('torchActive') is True)


def _editor_transition_errors(row, case_id, selection, body, cleanup):
    errors = []
    transitions = row.get('editorTransitions')
    if not isinstance(transitions, list):
        return ['Missing editor transition evidence list']
    enabled = selection['mode'] == 'toolkit'
    expected_enabled = enabled and case_id != 'p4-editor-off'
    if row.get('editorEnabled') is not expected_enabled:
        errors.append('Final editor setting differs from the required case state')
    required = {'case', 'enabled', 'at', 'boundary', 'current', 'actionRef', 'nativeRef',
                'generationBefore', 'generationAfter', 'tailRetained', 'requestRetained'}
    expected_count = (1 if case_id == 'p4-editor-off' else 2) if enabled and case_id in ('p4-editor-off', 'p4-editor-reenabled') else 0
    if len(transitions) != expected_count:
        errors.append('Editor transition count differs from the requested setting changes')
        return errors
    if expected_count == 0:
        return errors
    if any(not isinstance(item, dict) or not required.issubset(item) for item in transitions):
        return errors + ['Editor transition is missing required evidence fields']

    first = transitions[0]
    if (first.get('case') != case_id or first.get('enabled') is not False
            or first.get('boundary') != 'accepted-cancel'
            or first.get('current') != body.get('sequence')
            or first.get('actionRef') != body.get('actionRef')
            or first.get('nativeRef') != body.get('nativeRef')
            or type(first.get('generationBefore')) is not int or first['generationBefore'] < 0
            or type(first.get('generationAfter')) is not int
            or first['generationAfter'] not in (first['generationBefore'], first['generationBefore'] + 1)
            or first.get('tailRetained') is not True or first.get('requestRetained') is not True
            or not _number(first.get('at')) or first['at'] < row.get('boundary', {}).get('at', float('inf'))):
        errors.append('Editor-off transition lost the accepted active-read cancellation identity or retained work')
    if case_id == 'p4-editor-reenabled':
        second = transitions[1]
        if (second.get('case') != case_id or second.get('enabled') is not True
                or second.get('boundary') != 'cleanup-current'
                or second.get('current') != cleanup.get('sequence')
                or second.get('actionRef') != cleanup.get('actionRef')
                or second.get('nativeRef') not in (cleanup.get('nativeRef'), False)
                or second.get('nativeRef') is False and second.get('started') not in (None, False)
                or type(second.get('generationBefore')) is not int or second['generationBefore'] < 0
                or type(second.get('generationAfter')) is not int
                or second.get('generationAfter') != second.get('generationBefore')
                or second.get('tailRetained') is not True or second.get('requestRetained') is not False
                or not _number(second.get('at')) or second['at'] < first.get('at', float('inf'))):
            errors.append('Editor reenable transition did not target the current exact cleanup return')
    return errors


def check_case(row, case, selection, prepared, baseline, checkpoint, verified, receipts):
    errors = []
    try:
        enabled = selection['mode'] == 'toolkit'
        case_id = case
        case = base_case(case)
        keep = enabled and case == 'p4-keep-return'
        ids, b, actual, authority = row['ids'], row['baseline'], row['client'], row['server']
        if (row.get('status') != 'passed' or row.get('id') != case_id or ids != prepared or ids.get('case') != case_id
                or b != baseline or row['authorityBaseline'] != ids['baseline'] or row['checkpoint'] != checkpoint or authority != verified):
            errors.append('Exact raw authority/client evidence differs')
        items = ids['items']
        if len(set(items.values())) != len(items) or any(type(v) is not int or v <= 0 for v in items.values()):
            errors.append('Fixture item IDs missing or aliased')
        if selection['kind'] == 'mp' and (type(ids.get('actor')) is not int or ids['actor'] < 0):
            errors.append('Prepared native actor ID missing')
        def expected_inventory(rows):
            return [dict(entry, container='root') if keep and entry.get('id') == items.get('borrowed') else entry for entry in rows]
        if (actual['items'] != expected_inventory(b['items']) or authority['items'] != expected_inventory(ids['baseline']['items'])
                or not restored(actual, ids, keep) or not restored(authority, ids, keep)
                or actual.get('book') != ids['pages'] or authority.get('book') != ids['pages']
                or b.get('book') != ids['initial'] or ids['initial'] + 1 != ids['pages']):
            errors.append('Native cleanup, exact inventory conservation or tail completion failed')
        boundary = row['boundary']; records = row['records']
        expected_types = ('ISUnequipAction', 'ISEatFoodAction') if case == CASES[0] else ('ISInventoryTransferAction', 'ISReadABook')
        prep = [r for r in records if r.get('role') == 'prepare']; body = [r for r in records if r.get('role') == 'body']
        cleanup = [r for r in records if r.get('role') == 'cleanup']; tails = [r for r in records if r.get('role') == 'tail']
        replaced_return = enabled and case == CASES[1]
        if (len(prep) != 1 or len(body) != 1 or len(cleanup) != (2 if replaced_return else 1) or len(tails) != 1
                or (prep[0]['type'], body[0]['type']) != expected_types):
            errors.append('Missing/duplicate exact native prepare/body/cleanup/tail')
            return errors
        p, body, tail = prep[0], body[0], tails[0]
        retired = None
        if keep:
            retired = cleanup[0]
            if (retired.get('type') != 'ISInventoryTransferAction' or not retired.get('actionRef')
                    or retired.get('token') != body.get('token') or not body['sequence'] < retired['sequence'] < tail['sequence']):
                errors.append('Kept borrowed return lost exact same-operation identity/order')
            cleanup = retired
        elif replaced_return:
            # readItem already queued its native allowMissing return. Cancellation
            # discards that unstarted same-operation intent; the earned ledger
            # return is a separate action and token, with one actual native effect.
            retired = [r for r in cleanup if r.get('token') == body.get('token')]
            executed = [r for r in cleanup if r.get('token') != body.get('token')]
            if len(retired) != 1 or len(executed) != 1:
                errors.append('Borrowed return lacks exact retired/native and fresh/owned identities')
                return errors
            retired, cleanup = retired[0], executed[0]
            if (retired.get('type') != 'ISInventoryTransferAction' or cleanup.get('type') != 'ISInventoryTransferAction'
                    or retired.get('started') is not False or retired.get('progress') is not False
                    or retired.get('startedAt') is not None or retired.get('performedAt') is not None
                    or retired.get('finishes') != [] or retired.get('receipts') != []
                    or retired.get('transaction') not in (None, False) or retired.get('uuid') not in (None, False)
                    or retired.get('nativeRef') is not None or retired.get('transactionDone') is True
                    or not cleanup.get('token') or cleanup.get('token') == tail.get('token')
                    or not retired.get('actionRef') or retired.get('actionRef') == cleanup.get('actionRef')
                    or not body['sequence'] < retired['sequence'] < tail['sequence'] < cleanup['sequence']):
                errors.append('Retired borrowed native return ran, changed identity or lost its exact replacement')
        else:
            cleanup = cleanup[0]
        errors.extend(_editor_transition_errors(row, case_id, selection, body, cleanup))
        if retired is not None and (retired.get('started') is not False or retired.get('progress') is not False
                or any(retired.get(k) is not None for k in ('startedAt', 'performedAt', 'nativeRef'))
                or retired.get('finishes') != [] or retired.get('receipts') != []
                or retired.get('transaction') not in (None, False) or retired.get('uuid') not in (None, False)
                or retired.get('transactionDone') is True):
            errors.append('Explicitly retired native return executed or acquired native authority')
        if enabled and case != CASES[0]:
            ui = boundary.get('ui', {})
            target = cleanup if keep else body
            if (ui.get('source') != 'ActionQueuePanel.List' or ui.get('input') != 'programmatic-press-release'
                    or ui.get('header') is not (not keep) or ui.get('target') != target.get('sequence')
                    or ui.get('actionRef') != target.get('actionRef') or ui.get('item') != items['borrowed']
                    or any(ui.get(k) is not True for k in ('previewAllowed', 'pressed', 'pressCaptured', 'released', 'gestureCleared'))
                    or ui.get('feedback') is not False or not _number(ui.get('x')) or not _number(ui.get('y'))
                    or not _number(ui.get('at')) or ui['at'] < boundary.get('at', -1)
                    or keep and (ui.get('bodyCurrent') is not True or ui.get('returnAbsent') is not True
                                 or ui.get('bodyRef') != body.get('actionRef') or ui.get('nativeRef') != body.get('nativeRef'))):
                errors.append('Real Panel exact target preview/press/release evidence missing or changed')
        expected_items = {'prepare': items['mask' if case == CASES[0] else 'borrowed'],
                          'body': items['food' if case == CASES[0] else 'borrowed'],
                          'cleanup': items['mask' if case == CASES[0] else 'borrowed'],
                          'tail': items['book']}
        if any(record.get('role') not in expected_items or record.get('item') != expected_items.get(record.get('role')) for record in records):
            errors.append('Native action role has the wrong exact item ID')
        if (boundary.get('requested') is not enabled or enabled and boundary.get('allowed') is not True
                or any(boundary.get(k) is not True for k in ('preparationAbsent', 'preparationPaid', 'currentProgress', 'tailRetained'))
                or boundary.get('preparation') != p['sequence'] or boundary.get('body') != body['sequence']
                or not _number(p.get('performedAt')) or p['performedAt'] > boundary.get('at', -1)
                or not p.get('started') or not tail.get('started') or not tail.get('progress')
                or not keep and (not cleanup.get('performedAt') or not cleanup.get('started'))):
            errors.append('Cancellation did not follow confirmed native preparation or retain real cleanup/tail')
        if enabled and (not keep and cleanup['performedAt'] > tail.get('startedAt', -1) or not owned_cleanup_before_tail(row['tailSnapshot'], ids, keep)
                        or body['token'] != p['token'] or body['token'] == tail['token']):
            errors.append('Earned cleanup lost operation ownership or ran after the independent tail')
        if (row['outcome'].get('cleanupBeforeTail') is not owned_cleanup_before_tail(row['tailSnapshot'], ids, keep)
                or row['outcome'].get('originalEquipmentBeforeTail') is not restored(row['tailSnapshot'], ids, keep)):
            errors.append('Tail cleanup/equipment claim differs from the observed native hands and activation')
        if row.get('nativeMethodsUnchanged') is not True:
            errors.append('Native lifecycle methods changed')
        for record in records:
            transfer = record['type'] == 'ISInventoryTransferAction' and selection['kind'] == 'mp'
            valid_duration = _number(record.get('duration')) and (record['duration'] == -1 if transfer else record['duration'] > 1)
            if record.get('nativeMethods') is not True or not valid_duration:
                errors.append('Native constructor duration/lifecycle evidence invalid')
            callbacks = record.get('finishes', [])
            cancelled_body = enabled and case == CASES[1] and record is body
            unstarted_return = (replaced_return or keep) and record is retired
            if cancelled_body or unstarted_return:
                if callbacks or record.get('performedAt') is not None:
                    errors.append('Cancelled native read/retired return reported a lifecycle effect')
            else:
                # Native client perform settles against server authority. Its
                # complete callback is not required on the client (Lifecycle's
                # native needsComplete=false); SP must observe both boundaries.
                phases = [f.get('phase') for f in callbacks]
                allowed = (['perform'],) if selection['kind'] == 'mp' else (['perform', 'complete'],)
                if (phases not in allowed
                        or any(f.get('succeeded') is not True or not _number(f.get('at')) for f in callbacks)
                        or not _number(record.get('performedAt')) or not _number(record.get('startedAt'))
                        or not record['startedAt'] <= callbacks[0]['at'] <= record['performedAt']
                        or len(callbacks) == 2 and record['performedAt'] > callbacks[1]['at']):
                    errors.append('Exact successful native callback evidence missing or changed')
            if record.get('started'):
                effective = record.get('effectiveDuration')
                if not _number(effective) or effective <= 1:
                    errors.append('Missing actual native duration allocation')
                elif transfer:
                    if not _number(record.get('transactionDuration')) or abs(effective - record['transactionDuration']) > .001:
                        errors.append('Host transfer changed native transaction duration')
                else:
                    before, after = record.get('durationBefore'), record.get('durationAfter')
                    if (not _number(before) or not _number(after) or min(before, after) <= 1
                            or not min(before, after) - .001 <= effective <= max(before, after) + .001):
                        errors.append('Native duration allocation escaped its bracket')
        if case == CASES[0]:
            if not body.get('started') or not body.get('progress') or boundary['current'] != body['sequence']:
                errors.append('Mask boundary did not cancel an actual active meal')
            expected = b['food']['hunger'] - b['food']['base'] * .25
            if any(not _number(s['food'].get('hunger')) or abs(s['food']['hunger'] - expected) > .0001 for s in (actual, authority)):
                errors.append('Mask food portion was omitted, duplicated or altered')
        else:
            before = boundary['before']['borrowed']
            if (boundary['current'] != body['sequence'] or not p.get('transactionDone') or p.get('transactionRejected') is not False
                    or body.get('started') is not True or body.get('progress') is not True
                    or not _number(body.get('readStartProgress')) or not _number(body.get('readMaxProgress'))
                    or body['readMaxProgress'] <= body['readStartProgress'] + .00000001
                    or ids.get('borrowedType') != 'Base.BookFirstAid1' or ids.get('borrowedInitial') + 1 != ids.get('borrowedPages')
                    or before != {'pages': ids['borrowedInitial'], 'characterPages': ids['borrowedInitial'], 'total': ids['borrowedPages']}
                    or enabled and not keep and body.get('performedAt') is not None):
                errors.append('Borrowed native read did not cancel at its confirmed pickup/paid-page boundary')
            expected_pages = ids['borrowedInitial'] if enabled and not keep else ids['borrowedPages']
            expected = {'pages': expected_pages, 'characterPages': expected_pages, 'total': ids['borrowedPages']}
            if any(s.get('borrowed') != expected for s in (actual, authority, row['bodyTerminal'], row['tailSnapshot'])):
                errors.append('Borrowed paid pages rolled back or replayed after native stop/return')
            if enabled:
                operation = boundary.get('operationState', {})
                owned = [entry for entry in operation.get('borrowings', []) if entry.get('id') == items['borrowed']]
                if len(owned) != 1 or owned[0] != {'id': items['borrowed'], 'fullType': ids['borrowedType'], 'state': 'active'}:
                    errors.append('Exact confirmed P4 borrowing episode absent from shared operation phase record')
        if keep and any(snapshot.get('borrowedContainer') != 'root'
                        or snapshot.get('items') != expected_inventory(b['items'])
                        for snapshot in (row['bodyTerminal'], row['tailSnapshot'])):
            errors.append('Kept exact book returned or changed identity at body/tail completion')
        idle = row.get('idleEvidence', {})
        idle_snapshot = idle.get('snapshot', {})
        if (idle.get('case') != case_id or idle.get('empty') is not True or not _number(idle.get('since'))
                or not _number(idle.get('at')) or idle['at'] - idle['since'] < 1500
                or idle['since'] < tail.get('performedAt', float('inf'))
                or idle_snapshot.get('items') != actual.get('items') or not restored(idle_snapshot, ids, keep)
                or idle_snapshot.get('book') != ids['pages']
                or case != CASES[0] and idle_snapshot.get('borrowed') != actual.get('borrowed')):
            errors.append('Native/P4 idle failed exact late-return, equipment or independent-tail gate')
        if selection['kind'] == 'mp':
            for record in (p, cleanup):
                if keep and record is retired: continue
                if record['type'] == 'ISInventoryTransferAction':
                    if record.get('transactionDone') is not True or record.get('transactionRejected') is not False or not record.get('transaction'):
                        errors.append('Native transfer lacks an exact completed inventory transaction')
                    continue
                states = record.get('receipts', [])
                if (len(states) != 2 or [s.get('state') for s in states] != ['started', 'completed']
                        or states[0].get('token') != states[1].get('token') or states[0].get('transaction') != states[1].get('transaction')
                        or not isinstance(states[0].get('token'), str) or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', states[0]['token'])
                        or any(s.get('case') != case_id or type(s.get('player')) is not int or s['player'] != ids.get('actor')
                               or s.get('actionRef') != record['actionRef'] or not s.get('nativeRef')
                               or s.get('nativeRef') != record.get('nativeRef') or s.get('kind') != record['type'] or s not in receipts for s in states)):
                    errors.append('Exact native equipment started/completed receipt missing')
    except (KeyError, TypeError, ValueError, IndexError) as error:
        errors.append('Malformed cleanup evidence: ' + str(error))
    return errors


def verify(root, selection, catalog):
    root = Path(root); issues, outcomes = [], []
    cases = selection['cases']
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [r for r in report.events(text) if r.get('suite') == 'cleanup-cancel']
        setups = [r for r in events if r.get('event') == 'setup']; completed = [r for r in events if r.get('event') == 'complete']
        rows = [r for r in events if r.get('event') == 'case']
        if (len(setups) != 1 or setups[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
                or setups[0].get('nativeDurations') is not True or setups[0].get('cases') != cases
                or len(completed) != 1 or completed[0].get('performed') != len(cases) or completed[0].get('failed') != 0
                or completed[0].get('skipped') != 0 or completed[0].get('cases') != cases or not complete(selection, 'client1', text)):
            issues.append('Missing exact cleanup setup/completion gates')
        specs, baselines, checkpoints, verified = (raw(authority if name != 'BASELINE' else text, name) for name in ('PREPARED', 'BASELINE', 'CHECKPOINT', 'VERIFY'))
        if ([r.get('id') for r in rows] != cases or any([r.get('case') for r in rs] != cases for rs in (specs, baselines, checkpoints, verified))):
            issues.append('Missing/duplicate/reordered cleanup case evidence')
        receipts = raw(text, 'NATIVE_STATE')
        editor_transitions = raw(text, 'EDITOR_TRANSITION')
        expected_editor_transitions = [transition for row in rows for transition in row.get('editorTransitions', [])]
        if editor_transitions != expected_editor_transitions:
            issues.append('Raw editor setting transitions differ from per-case evidence or are missing/duplicated')
        confirmed = raw(authority, 'BASELINE_CONFIRMED')
        if confirmed != [r.get('authorityBaseline') for r in rows] or confirmed != [r.get('baseline') for r in specs]:
            issues.append('Exact current authority baseline acknowledgement missing or changed')
        boundaries, tails = raw(text, 'BOUNDARY'), raw(text, 'TAIL_STARTED')
        settled = raw(text, 'BODY_SETTLED')
        if settled != [r.get('bodyTerminal') for r in rows if base_case(r.get('id')) != BASE_CASES[0]]:
            issues.append('Raw borrowed native body settlement missing, changed or duplicated')
        if (len(boundaries) != len(cases) or [r.get('case') for r in tails] != cases
                or boundaries != [r.get('boundary') for r in rows] or tails != [r.get('tailSnapshot') for r in rows]):
            issues.append('Raw native boundary/tail evidence missing, changed, duplicated or out of order')
        if raw(text, 'P4_IDLE') != [r.get('idleEvidence') for r in rows]:
            issues.append('Raw native/P4 idle evidence missing, changed or duplicated')
        for i, case in enumerate(cases):
            row = rows[i] if i < len(rows) else {}
            errors = check_case(row, case, selection, specs[i] if i < len(specs) else None, baselines[i] if i < len(baselines) else None,
                                checkpoints[i] if i < len(checkpoints) else None, verified[i] if i < len(verified) else None, receipts)
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('Cleanup actor/kind/mode differs')
            issues += [case + ': ' + error for error in errors]
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                                 outcome={name: not errors and value for name, value in row.get('outcome', {}).items()}))
    except (OSError, ValueError, TypeError, AttributeError) as error:
        issues.append('Cleanup verifier ' + str(error))
    return dict(issues=issues, outcomes=outcomes)
