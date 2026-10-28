"""Opt-in native book control bank: exact source, real Panel gesture and authority effects."""
import copy
import json
from pathlib import Path
import re
import shutil

from .. import report
from .tv_controls import MODS, _number

SOURCES = ('root', 'worn-bag', 'world')
CONTROLS = ('header-cancel', 'reader-child-cancel', 'move-equip', 'move-volume')
CASES = tuple(source + '/' + control for source in SOURCES for control in CONTROLS) + tuple(source + '/return-child-cancel' for source in SOURCES if source != 'root')
CAPACITY_CASES = tuple(source + '/' + control + '-capacity-lost' for source in SOURCES if source != 'root' for control in ('header-cancel', 'move-volume'))
CASES += CAPACITY_CASES
PREFIX = '[BOOK_CONTROLS] '

def base_control(control):
    return control.removesuffix('-capacity-lost')

GAME_INPUTS = (
    'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua',
    'media/lua/shared/TimedActions/ISReadABook.lua',
    'media/lua/client/TimedActions/ISInventoryTransferAction.lua',
    'media/lua/shared/TimedActions/ISTransferAction.lua',
    'media/lua/shared/TimedActions/ISEquipWeaponAction.lua',
    'media/lua/shared/RadioCom/ISRadioAction.lua',
    'media/lua/client/RadioCom/RadioWindowModules/RWMVolume.lua',
    'media/lua/client/RadioCom/RadioWindowModules/RWMPanel.lua',
    'media/lua/client/ISUI/ISScrollingListBox.lua',
    'media/lua/client/TimedActions/ISTimedActionQueue.lua',
    'media/scripts/generated/items/container.txt',
)


def definitions():
    checks = {name: {case: dict(effectsVerified=True, serverAuthorityVerified=True) for case in CASES}
              for name in ('success-queued', 'server-authority')}
    return {'book-controls': dict(status='ready', clients=1, default_mods=list(MODS), game_inputs=list(GAME_INPUTS),
        scenario_actions={'source-bound-book-controls': dict(checks=checks,
            scope='Opt-in ordered eighteen-case source/control bank. Favorite Carpentry skillbook from root, worn military bag or direct world shelf; native onLiteratureItems/readItem owns pickup/read/return. Real Panel hit-tested singleton/header/reader-child cross, exact optional-return child cancellation that keeps reading and the book carried, or pending native Pen equip/TV RWM SetVolume drag before the progressed active reader. Empty authority hands and exact root Pen expose unrelated equipment/borrowed-return interactions. Queue-off controls run unchanged native producers naturally. Fresh reader and saved page, old Java drain, exact returned item/container, final explicit Pen hand intent, native durations/callback identity, Host equipment/radio outcomes, full inventory/worn/hands/appearance snapshots and independent native reader tail. All functional control denials are collected through normal native clear/drain, then the aggregate fails. One EN actor, full selected pack, disposable macOS SP/menu Host. Programmatic widget gestures, no physical pointer/rendering claim.')},
        cases=[dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'], modes=['native', 'toolkit'], languages=['EN']) for case in CASES])}


def validate(selection):
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('book_controls') is not True
            or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Book controls require book_controls=true, the exact ordered eighteen-case bank, full selected EN pack, fresh SP/menu Host and one client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    code = Path(project) / 'PZSurvivorToolkit/42/media/lua'
    return [Path(__file__).with_name('tv_controls.py'), Path(__file__).parents[1] / 'mod_selection.py',
            Path(project) / 'tests/test_queue_book_controls.py',
            *sorted((root / 'book-controls').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            code / 'client/PZSurvivorToolkit/ActionQueuePanel.lua', code / 'client/PZSurvivorToolkit/ActionQueueProjection.lua',
            code / 'shared/PZSurvivorToolkit/SourceProof.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for package in ('book-controls', 'startup'):
            for path in sorted((root / package).rglob('*.lua')):
                target = lua / path.relative_to(root / package)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
        for path in (root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua'):
            target = lua / 'shared' / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL book-controls'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def raw(text, marker):
    return [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]


def complete(selection, role, text):
    """A complete diagnostic bank terminates even when feature cases were denied."""
    try:
        values = raw(text, 'COMPLETE')
        return (role == 'client1' and len(values) == 1 and values[0].get('cases') == list(CASES)
                and type(values[0].get('failed')) is int and 0 <= values[0]['failed'] <= len(CASES))
    except (ValueError, TypeError):
        return False


def expected(ids, enabled, boundary):
    value = copy.deepcopy(ids['baseline'])
    control = base_control(ids['control']); lost = control != ids['control']
    cancelled = enabled and control in ('header-cancel', 'reader-child-cancel')
    for name in ('front', 'tail'):
        pages = boundary['before']['books']['front']['pages'] if name == 'front' and cancelled else ids['tail']['initial'] if name == 'tail' and lost and not enabled else ids[name]['total']
        value['books'][name]['pages'] = value['books'][name]['characterPages'] = pages
    if lost or enabled and control == 'return-child-cancel':
        value['books']['front']['container'] = 'root'
        for entry in value['items']:
            if entry['id'] == ids['front']['id']: entry['container'] = 'root'
    value['volume'] = ids['initialVolume'] if lost and not enabled else ids['targetVolume']
    value['hands']['primary'] = False if lost and not enabled else ids['pen']['id']
    return value


def _record_errors(record, kind, case, actor, acks, capacity_lost=False):
    errors = []
    role = record.get('role')
    if (record.get('nativeSource') is not True or not record.get('actionRef') or type(record.get('sequence')) is not int
            or type(record.get('started')) is not bool or type(record.get('progress')) is not bool):
        errors.append('Missing exact source-bound native admission')
    if role in ('front', 'tail', 'volume', 'equip'):
        if not _number(record.get('duration')) or record['duration'] <= 1:
            errors.append('Native constructor duration missing/shortened')
        if role == 'volume' and (record.get('duration') != 30 or record.get('mode') != 'SetVolume'):
            errors.append('Native TV SetVolume constructor changed')
    if record.get('started'):
        if not record.get('nativeRef') or not _number(record.get('startedAt')) or not _number(record.get('allocatedAt')):
            errors.append('Native allocation/start identity missing')
        effective = record.get('effectiveDuration')
        if role in ('front', 'tail', 'volume', 'equip'):
            before, after = record.get('durationBefore'), record.get('durationAfter')
            if (not all(_number(v) and v > 1 for v in (before, after, effective))
                    or not min(before, after) - .001 <= effective <= max(before, after) + .001):
                errors.append('Native allocation is outside its live duration bracket')
        if role in ('volume', 'equip', 'tail') and (record.get('progress') is not True or not _number(record.get('performedAt'))):
            errors.append('Independent native action never progressed/performed')
    if record.get('performedAt') is not None and role in ('front', 'tail', 'volume', 'equip'):
        callbacks = record.get('finishes', [])
        expected_phases = ['perform'] if kind == 'mp' else ['perform', 'complete']
        if ([c.get('phase') for c in callbacks] != expected_phases
                or any(c.get('succeeded') is not True or not _number(c.get('at')) for c in callbacks)):
            errors.append('Native successful perform/complete callback evidence missing or changed')
    if kind == 'mp' and record.get('started') and role in ('volume', 'equip'):
        receipts = record.get('receipts', [])
        if (len(receipts) != 2 or [r.get('state') for r in receipts] != ['started', 'completed']
                or any(r not in acks or r.get('case') != case or r.get('sequence') != record.get('sequence')
                       or r.get('kind') != record.get('type') or r.get('player') != actor for r in receipts)
                or receipts[0].get('token') != receipts[1].get('token')
                or receipts[0].get('transaction') != receipts[1].get('transaction')
                or type(receipts[0].get('transaction')) is not int or receipts[0]['transaction'] <= 0
                or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(receipts[0].get('token')))):
            errors.append('Missing sealed native equipment/radio started/completed outcome')
    if kind == 'mp' and record.get('role') in ('pickup', 'return') and record.get('started') and not (capacity_lost and role == 'return'):
        if not record.get('transaction') or record.get('transactionDone') is not True or record.get('transactionRejected') is not False:
            errors.append('Native book transfer has no successful exact inventory transaction')
    return errors


def performance_errors(value, case, enabled):
    errors = []
    if (not isinstance(value, dict) or value.get('case') != case or value.get('timer') != 'getTimestampMs'
            or value.get('units') != 'ms' or value.get('coarse') is not True or value.get('readOnly') is not True
            or value.get('queueEnabled') is not enabled or type(value.get('queueCount')) is not int or not 1 <= value['queueCount'] <= 30
            or value.get('warmup') != 3 or value.get('samples') != 20 or not isinstance(value.get('limits'), str)):
        return ['Missing bounded read-only coarse-clock performance evidence']
    metrics = value.get('metrics', [])
    expected_names = ['evaluateMove', 'evaluateCancel', 'previewMove', 'previewCancel', 'panelUpdate']
    if not isinstance(metrics, list) or [m.get('name') for m in metrics if isinstance(m, dict)] != expected_names:
        return ['Missing/duplicate actual Policy/Panel timing entrypoints']
    for index, metric in enumerate(metrics):
        kind = 'authoritative' if index < 2 else 'advisory'
        raw = metric.get('rawMs')
        budgets = (2, 4) if index < 2 else (1, 2)
        if (metric.get('kind') != kind or not _number(metric.get('firstUseMs')) or metric['firstUseMs'] < 0
                or not isinstance(raw, list) or len(raw) != 20 or any(not _number(v) or v < 0 for v in raw)
                or (metric.get('p95BudgetMs'), metric.get('p99BudgetMs')) != budgets):
            errors.append('Malformed raw timings/warmup separation/frozen budget: ' + expected_names[index]); continue
        ordered = sorted(raw); p95, p99 = ordered[18], ordered[19]
        if metric.get('p95Ms') != p95 or metric.get('p99Ms') != p99 or metric.get('passed') is not (p95 <= budgets[0] and p99 <= budgets[1]):
            errors.append('Timing quantile or pass claim differs from raw samples: ' + expected_names[index])
        if p95 > budgets[0] or p99 > budgets[1]:
            errors.append('Frozen performance budget exceeded: ' + expected_names[index])
    return errors


def check_case(row, case, selection, prepared, authority_baseline, authority_final, admissions, boundaries, drains, acks, capacity_authority=None):
    errors = []
    try:
        enabled = selection['mode'] == 'toolkit'
        source, original_control = case.split('/')
        control = base_control(original_control); lost = original_control != control
        keep = enabled and control == 'return-child-cancel'
        ids, boundary, records = row['ids'], row['boundary'], row['records']
        errors.extend(performance_errors(row.get('performance'), case, enabled))
        if isinstance(row.get('performance'), dict) and row['performance'].get('queueCount') != len(boundary.get('queue', [])):
            errors.append('Timing queue shape differs from the real edit boundary')
        spacing = row.get('tickSpacingMs')
        if not isinstance(spacing, list) or not spacing or len(spacing) > 60 or any(not _number(v) or v < 0 for v in spacing):
            errors.append('Missing bounded real tick-spacing observations')
        if (row.get('id') != case or row.get('status') != 'passed' or ids != prepared or ids.get('case') != case
                or ids.get('source') != source or ids.get('control') != original_control or ids.get('front', {}).get('type') != 'Base.BookCarpentry1'
                or ids.get('tail', {}).get('type') != 'Base.BookCooking1' or ids.get('pen', {}).get('type') != 'Base.Pen'
                or ids.get('initialVolume') != .5 or ids.get('targetVolume') != .25
                or ids['front']['total'] - ids['front']['initial'] != 2 or ids['tail']['total'] - ids['tail']['initial'] != 1
                or row.get('baseline') != ids['baseline'] or row.get('authorityBaseline') != authority_baseline
                or authority_baseline != ids['baseline'] or row.get('server') != authority_final
                or row.get('nativeMethodsUnchanged') is not True):
            errors.append('Exact source, seeded IDs, raw authority baseline/final or native methods differ')
        ids_list = [ids[name]['id'] for name in ('front', 'tail', 'pen')]
        if source == 'worn-bag':
            ids_list.append(ids['bag']['id'])
            if ids['bag'].get('type') != 'Base.Bag_Military' or ids['baseline'].get('bagWorn') is not True:
                errors.append('Exact worn military bag source missing')
        elif ids.get('bag') is not False:
            errors.append('Unexpected source bag')
        if len(set(ids_list)) != len(ids_list) or any(type(v) is not int or v <= 0 for v in ids_list):
            errors.append('Fixture IDs missing or aliased')
        if ids['baseline'].get('hands') != {'primary': False, 'secondary': False}:
            errors.append('Native Pen must start with empty authority hands')
        if ids['baseline']['books']['front'].get('container') != source or any(ids['baseline']['books'][name].get('favorite') is not True for name in ('front', 'tail')):
            errors.append('Favorite book source container changed before producer')
        required = expected(ids, enabled, boundary)
        if row.get('client') != required or row.get('server') != required:
            errors.append('Exact inventory/container conservation, paid pages, TV volume, Pen hand intent or untouched equipment/appearance failed')
        if lost:
            capacity = row.get('capacity', {})
            if (capacity != capacity_authority or capacity.get('case') != case or capacity.get('source') != source
                    or capacity.get('itemId') != ids['front']['id'] or capacity.get('itemType') != ids['front']['type']
                    or capacity.get('actor') != ids['actor'] or capacity.get('authority') is not True
                    or capacity.get('bookRoot') is not True or capacity.get('after') != 0 or capacity.get('roomAfter') is not False
                    or not _number(capacity.get('before')) or capacity['before'] <= 0
                    or not _number(capacity.get('requestedAt')) or not _number(capacity.get('at'))
                    or not boundary.get('at', float('inf')) <= capacity['requestedAt'] <= capacity['at']
                    or row.get('returnSucceeded') is not False):
                errors.append('Missing exact authority capacity loss after the accepted edit/native control boundary')
            if enabled:
                debt, ui = row.get('blockedReturn', {}), row.get('failureUI', {})
                if (not isinstance(debt, dict) or not debt.get('id') or debt.get('itemId') != ids['front']['id']
                        or debt.get('itemType') != ids['front']['type'] or debt.get('state') != 'blocked'
                        or debt.get('reason') not in ('admission', 'server', 'unmoved')
                        or not isinstance(ui, dict) or ui.get('source') != 'ActionQueuePanel.KeepReturn'
                        or ui.get('input') != 'programmatic-press-callback' or ui.get('id') != debt.get('id')
                        or ui.get('itemId') != ids['front']['id'] or ui.get('count') != 1
                        or any(ui.get(k) is not True for k in ('visible', 'idle', 'bookRoot', 'pressCaptured', 'cleared', 'bookRetained'))
                        or not _number(ui.get('at')) or ui['at'] < capacity.get('at', float('inf'))
                        or capacity.get('acceptedAt') != boundary.get('ui', {}).get('acceptedAt')
                        or not _number(capacity.get('acceptedAt')) or capacity['acceptedAt'] > capacity['requestedAt']):
                    errors.append('Failed return was not retained visibly with exact identity and explicitly kept through the real idle footer')
            elif row.get('blockedReturn') is not False or row.get('failureUI') is not False or capacity.get('acceptedAt') is not False or row.get('nativeDebtAbsent') is not True:
                errors.append('Queue-off capacity control acquired editor debt/Keep UI')
        elif row.get('capacity') not in (None, False) or row.get('blockedReturn') not in (None, False) or row.get('failureUI') not in (None, False):
            errors.append('Normal source/control case acquired capacity intervention or failed-return UI')
        if (len(admissions) != 1 or admissions[0].get('producer') != 'ISInventoryPaneContextMenu.onLiteratureItems/readItem'
                or admissions[0].get('volumeProducer') != 'RWMVolume.onVolumeChange'
                or admissions[0].get('equipProducer') != 'ISInventoryPaneContextMenu.equipWeapon'
                or admissions[0].get('sourceBound') is not True or len(boundaries) != 1
                or boundaries[0] != dict({k: v for k, v in boundary.items() if k not in ('drained', 'drainedAt')}, drained=False)):
            errors.append('Missing unique actual native producers and raw UI boundary')
        if (len(drains) != 1 or drains[0] != dict(case=case, reader=boundary.get('reader'), native=boundary.get('native'),
                at=boundary.get('drainedAt'), oldNativeAbsent=True) or not _number(boundary.get('drainedAt'))
                or boundary['drainedAt'] < boundary.get('at', float('inf'))):
            errors.append('Exact old Java allocation removal receipt missing')
        admission = admissions[0].get('queue', []) if len(admissions) == 1 else []
        initial_roles = [r.get('role') for r in admission if r.get('role') != 'preparation']
        if initial_roles != ((['pickup', 'front', 'return'] if source != 'root' else ['front']) + ['equip', 'volume', 'tail']):
            errors.append('Actual literature source pickup/read/return or independent producer chain differs')
        if enabled:
            front_tokens = [r.get('token') for r in admission if r.get('role') in ('pickup', 'front', 'return')]
            separate = [r.get('token') for r in admission if r.get('role') in ('equip', 'volume', 'tail')]
            if (not front_tokens or type(front_tokens[0]) is not int or len(set(front_tokens)) != 1
                    or any(type(t) is not int for t in separate) or len(set(separate + front_tokens[:1])) != 4):
                errors.append('Native source operation lost pickup/read/return identity or independent tokens')
        if (boundary.get('requested') is not enabled or any(boundary.get(k) is not True for k in ('tailRetained', 'volumePending', 'equipPending', 'drained'))
                or not _number(boundary.get('at')) or not _number(boundary.get('delta')) or not 0 < boundary['delta'] < 1
                or boundary['before']['books']['front']['pages'] != ids['front']['initial'] + 1
                or boundary['before']['books']['front']['characterPages'] != ids['front']['initial'] + 1
                or boundary['before']['books']['tail']['pages'] != ids['tail']['initial']):
            errors.append('Edit did not target one paid page, active read and untouched independent work')
        front = [r for r in records if r.get('role') == 'front']
        others = {name: [r for r in records if r.get('role') == name] for name in ('tail', 'equip', 'volume')}
        moving = enabled and control.startswith('move-')
        if len(front) != (2 if moving else 1) or any(len(v) != 1 for v in others.values()):
            return errors + ['Duplicate/missing exact native reader, Pen equip, volume or unrelated tail']
        original = front[0]; tail, equip, volume = (others[n][0] for n in ('tail', 'equip', 'volume'))
        if (original.get('actionRef') != boundary.get('reader') or original.get('nativeRef') != boundary.get('native')
                or original.get('item') != ids['front']['id'] or original.get('started') is not True or original.get('progress') is not True
                or tail.get('item') != ids['tail']['id'] or equip.get('item') != ids['pen']['id']
                or equip.get('type') != 'ISEquipWeaponAction' or volume.get('type') != 'ISRadioAction'):
            errors.append('Exact active reader/independent native item identity differs')
        ui = boundary.get('ui')
        if enabled:
            if (not isinstance(ui, dict) or ui.get('source') != 'ActionQueuePanel.List'
                    or ui.get('input') != ('programmatic-drag' if moving else 'programmatic-press-release')
                    or any(ui.get(k) is not True for k in ('hitTested', 'pressCaptured', 'gestureCleared', 'accepted'))
                    or ui.get('feedback') is not False or ui.get('singleton') is not (source == 'root')
                    or ui.get('header') is not (source != 'root' and control not in ('reader-child-cancel', 'return-child-cancel'))
                    or ui.get('decision', {}).get('reason') is not False or ui.get('decision', {}).get('source') != source):
                errors.append('Actual hit-tested Panel gesture, exact header/child/singleton mapping or decision denied')
            if ui.get('operation') != original.get('token') or type(original.get('token')) is not int:
                errors.append('Real Panel operation identity missing')
            if keep:
                retired = [r for r in records if r.get('role') == 'return' and r.get('token') == original.get('token')]
                if (len(retired) != 1 or ui.get('target') != retired[0].get('actionRef')
                        or any(ui.get(k) is not True for k in ('bodyContinues', 'returnAbsent', 'bookRoot'))
                        or ui.get('operationCancelled') is not False
                        or retired[0].get('started') is not False or retired[0].get('progress') is not False
                        or retired[0].get('finishes') != [] or retired[0].get('receipts') != []
                        or any(retired[0].get(k) is not None for k in ('nativeRef', 'performedAt', 'startedAt', 'allocatedAt'))
                        or retired[0].get('transaction') not in (None, False)):
                    errors.append('Optional return cross stopped the reader, ran the retired return or lost exact keep intent')
            if moving and (ui.get('dragging') is not True or ui.get('movingAction') != (equip if control == 'move-equip' else volume).get('actionRef')
                    or ui.get('movingToken') != (equip if control == 'move-equip' else volume).get('token') or not ui.get('movingAnchor')):
                errors.append('Move gesture never crossed the drag threshold')
        elif ui is not False or row.get('reset') is not False:
            errors.append('Queue-off natural control performed an edit/reset')
        starts = row.get('starts', [])
        expected_roles = (['front', 'equip', 'front', 'volume', 'tail'] if control == 'move-equip' else
                          ['front', 'volume', 'front', 'equip', 'tail']) if moving else ['front'] if lost and not enabled else ['front', 'equip', 'volume', 'tail']
        by_sequence = {r.get('sequence'): r for r in records}
        if len(by_sequence) != len(records) or [by_sequence.get(i, {}).get('role') for i in starts if by_sequence.get(i, {}).get('role') in ('front', 'equip', 'volume', 'tail')] != expected_roles:
            errors.append('Pen/volume/read start order differs from the actual requested priority direction')
        expected_started = {r.get('sequence') for r in records if r.get('started') and r.get('role') in ('front', 'equip', 'volume', 'tail')}
        observed_started = [i for i in starts if by_sequence.get(i, {}).get('role') in ('front', 'equip', 'volume', 'tail')]
        if set(observed_started) != expected_started or len(observed_started) != len(expected_started):
            errors.append('Native started flags and exact start sequence disagree')
        if moving:
            resumed, receipt = front[1], row.get('resume', {})
            if (not isinstance(receipt, dict) or receipt.get('oldAction') != original.get('actionRef') or receipt.get('newAction') != resumed.get('actionRef')
                    or receipt.get('oldNative') != original.get('nativeRef') or receipt.get('newNative') != resumed.get('nativeRef')
                    or receipt.get('newAction') == receipt.get('oldAction') or receipt.get('newNative') == receipt.get('oldNative')
                    or receipt.get('oldNativeAbsent') is not True or receipt.get('item') != ids['front']['id']
                    or receipt.get('token') != original.get('token') or resumed.get('token') != original.get('token')
                    or receipt.get('startPage') != boundary['before']['books']['front']['pages']
                    or receipt.get('pages') != receipt.get('startPage') or resumed.get('progress') is not True):
                errors.append('Priority edit failed native stop/drain, fresh same-item/token reader or saved page resume')
        elif row.get('resume') is not False:
            errors.append('Unexpected fresh read after cancellation/natural control')
        for record in records:
            errors.extend(_record_errors(record, selection['kind'], case, ids['actor'], acks, lost))
        if (not enabled or moving or keep) and not _number(front[-1].get('performedAt')):
            errors.append('Naturally finished/resumed reader never performed')
        elif enabled and not moving and not keep and (original.get('performedAt') is not None or [c.get('phase') for c in original.get('finishes', [])] != ['stop']):
            errors.append('Cancelled original reader performed its remaining page')
        if not (lost and not enabled) and row.get('tailSnapshot', {}).get('books', {}).get('front') != required['books']['front']:
            errors.append('Book return/paid page was not settled before independent tail')
        if not (lost and not enabled) and row.get('tailSnapshot', {}).get('hands') != required['hands']:
            errors.append('Explicit Pen equip intent did not survive before the unrelated tail')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        errors.append('Malformed book-controls evidence: ' + str(error))
    return errors


def verify(root, selection, catalog):
    root = Path(root); issues, outcomes = [], []
    try:
        validate(selection)
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [r for r in report.events(text) if r.get('suite') == 'book-controls']
        setup = [r for r in events if r.get('event') == 'setup']; rows = [r for r in events if r.get('event') == 'case']; final = [r for r in events if r.get('event') == 'complete']
        if (len(setup) != 1 or setup[0].get('cases') != list(CASES)
                or any(setup[0].get(k) is not True for k in ('nativeDurations', 'sourceBound', 'authorityEquipment'))
                or setup[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
                or len(final) != 1 or final[0].get('cases') != list(CASES) or final[0].get('performed') != len(CASES)
                or final[0].get('failed') != 0 or final[0].get('skipped') != 0 or any(r.get('event') == 'fatal' for r in events)):
            issues.append('Missing complete ordered book-controls qualification bank or functional denials remain')
        prepared, baselines, verified = (raw(authority, marker) for marker in ('PREPARED', 'BASELINE', 'VERIFIED'))
        if [r.get('id') for r in rows] != list(CASES) or any([r.get('case') for r in values] != list(CASES) for values in (prepared, baselines, verified)):
            issues.append('Cases or raw authoritative snapshots missing, duplicated or reordered')
        capacities = raw(authority, 'CAPACITY_LOST')
        if [r.get('case') for r in capacities] != list(CAPACITY_CASES): issues.append('Capacity interventions missing, duplicated or reordered')
        admissions, boundaries, drains, acks = (raw(text, marker) for marker in ('ADMISSION', 'BOUNDARY', 'DRAIN', 'ACK'))
        timing_rows = raw(text, 'PERFORMANCE')
        if [r.get('case') for r in timing_rows] != list(CASES): issues.append('Timing evidence missing, duplicated or reordered')
        debts, failure_uis = raw(text, 'BLOCKED_RETURN'), raw(text, 'FAILURE_UI')
        expected_failures = list(CAPACITY_CASES) if selection['mode'] == 'toolkit' else []
        if [r.get('case') for r in debts] != expected_failures or [r.get('case') for r in failure_uis] != expected_failures:
            issues.append('Exact blocked-return and actual footer evidence missing, duplicated or reordered')
        for i, case in enumerate(CASES):
            row = rows[i] if i < len(rows) else {}
            errors = check_case(row, case, selection, prepared[i] if i < len(prepared) else None,
                baselines[i] if i < len(baselines) else None, verified[i] if i < len(verified) else None,
                [r for r in admissions if r.get('case') == case], [r for r in boundaries if r.get('case') == case], [r for r in drains if r.get('case') == case], [r for r in acks if r.get('case') == case], next((r for r in capacities if r.get('case') == case), None))
            if [r for r in timing_rows if r.get('case') == case] != [row.get('performance')]:
                errors.append('Raw performance evidence differs from the qualified case')
            if case in expected_failures:
                debt_rows = [r for r in debts if r.get('case') == case]
                ui_rows = [r for r in failure_uis if r.get('case') == case]
                if len(debt_rows) != 1 or debt_rows[0].get('entry') != row.get('blockedReturn') or ui_rows != [row.get('failureUI')]:
                    errors.append('Raw failed-return/footer evidence differs from the qualified case')
            if row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']:
                errors.append('Native case actor/kind/mode differs')
            issues.extend(case + ': ' + error for error in errors)
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors, serverAuthorityVerified=not errors)))
        if raw(text, 'DENIED') or raw(text, 'RESET'):
            issues.append('Real Panel control denied; collected diagnostic/reset bank is not a qualification pass')
        if not complete(selection, 'client1', text): issues.append('Missing unique diagnostic-bank completion')
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        issues.append('Book controls verifier ' + type(error).__name__ + ': ' + str(error))
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Programmatic real widget hit tests and handlers with an injected drag-threshold state; no physical pointer or rendering claim.',
        'Root singleton cross has no fabricated header; bag/world exercise actual operation/reader/optional-return controls. Four after-edit capacity failures retain an exact visible optional-return obligation, then explicitly Keep the item. Queue-off controls retain native rejected-return/tail-reset behavior.',
        'One favorite skillbook type isolates source ancestry; no assertion about magazines/comics or older game builds.']})
