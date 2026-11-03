"""Post-run book control checks over the original native observation receipts."""
import copy
import json
import math
from pathlib import Path
import re

from .. import report
from .book_controls import (
    CAPACITY_CASES, DEVICE_ONLY_CASES, FAVORITE_CASES, complete, raw, selected_cases, validate,
)
from .tv_controls import _number as _base_number


def _number(value):
    # JSON integers may exceed the float range used by math.isfinite.
    try:
        return _base_number(value)
    except OverflowError:
        return False


CLOCK_INFO = dict(schema=1, timer='System.nanoTime', units='ms', monotonic=True, relativeOrigin=True,
                  source='disposable-jvm-probe', functionClass='net.alexredby.bookcontrolsprobe.Main$MonotonicClock', nativeClock=True)


PERFORMANCE_SCOPE = dict(measurementScope='isolated-entrypoint-bank', completeEditMeasured=False, frameLoadMeasured=False,
                         firstUseScope='first-sample-of-this-bank-not-cold-process',
                         tailEstimate='20-samples-p95-order19-p99-sample-maximum', timerOverhead='included-not-subtracted')


ASSESSMENT_POLICY = dict(assessmentPolicy='correctness-work-complexity-and-impact', performanceAssessment='not-assessed')


def clock_errors(value):
    if (not isinstance(value, dict) or set(value) != set(CLOCK_INFO)
            or type(value.get('schema')) is not int or value != CLOCK_INFO
            or any(value.get(k) is not True for k in ('monotonic', 'relativeOrigin', 'nativeClock'))):
        return ['Missing source-bound monotonic millisecond clock evidence']
    return []


def handler_timing_errors(ui, precise, enabled):
    value = ui.get('handlerTiming') if isinstance(ui, dict) else None
    if not precise:
        return ['Unexpected unbound handler timing'] if value is not None else []
    if not enabled:
        return ['Queue-off control claimed an editor handler'] if value is not None else []
    fixed = dict(timer='System.nanoTime', units='ms', scope='actual-list-handler-work', samples=1, replayed=False,
                 includesHumanPause=False, includesRender=False, includesAsyncSettlement=False,
                 warmState='after-readonly-bank-and-diagnostic-decision', completeEditQualified=False, timerOverhead='included-not-subtracted')
    times = ('pressMs', 'releaseMs', 'handlerWorkMs', 'pressStartedMs', 'pressFinishedMs', 'releaseStartedMs', 'releaseFinishedMs')
    fields = set(fixed) | set(times)
    if (not isinstance(value, dict) or set(value) != fields or type(value.get('samples')) is not int
            or any(value.get(k) != v for k, v in fixed.items())
            or any(value.get(k) is not False for k in ('replayed', 'includesHumanPause', 'includesRender', 'includesAsyncSettlement', 'completeEditQualified'))
            or any(not _number(value.get(k)) or value[k] < 0 for k in times)):
        return ['Malformed single-use actual handler timing or unsupported latency claim']
    if (not value['pressStartedMs'] <= value['pressFinishedMs'] <= value['releaseStartedMs'] <= value['releaseFinishedMs']
            or not math.isclose(value['pressMs'], value['pressFinishedMs'] - value['pressStartedMs'], rel_tol=1e-12, abs_tol=1e-6)
            or not math.isclose(value['releaseMs'], value['releaseFinishedMs'] - value['releaseStartedMs'], rel_tol=1e-12, abs_tol=1e-6)):
        return ['Handler durations differ from their monotonic time intervals']
    if not math.isclose(value['handlerWorkMs'], value['pressMs'] + value['releaseMs'], rel_tol=1e-12, abs_tol=1e-9):
        return ['Handler work total differs from the single press/release observations']
    return []


def _action_identity(value):
    """Kahlua table dumps contain mutable fields after the stable class/address."""
    if not isinstance(value, str) or not value:
        return None
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]* 0x', value):
        match = re.fullmatch(r'([A-Za-z_][A-Za-z0-9_]* 0x[0-9a-fA-F]+)(?:\{.*\})?', value, re.DOTALL)
        return match.group(1) if match else None
    return value


def _same_action(left, right):
    identity = _action_identity(left)
    return identity is not None and identity == _action_identity(right)


def device_only(control):
    return control in ('move-volume-device-only', 'demote-reader-device-only')


def base_control(control):
    if device_only(control):
        return control.removesuffix('-device-only')
    return control.removesuffix('-capacity-lost') if control.endswith('-capacity-lost') else control.removesuffix('-favorite')


def capacity_case(control):
    return control.endswith('-capacity-lost')


def favorite_case(control):
    return control.endswith('-favorite')


def expected(ids, enabled, boundary, kind='mp'):
    value = copy.deepcopy(ids['baseline'])
    control = base_control(ids['control']); lost = capacity_case(ids['control']); favorite_unmoved = favorite_case(ids['control']) and kind == 'sp'
    cancelled = enabled and control in ('header-cancel', 'reader-child-cancel')
    for name in ('front', 'tail'):
        pages = boundary['before']['books']['front']['pages'] if name == 'front' and cancelled else ids['tail']['initial'] if name == 'tail' and lost and not enabled else ids[name]['total']
        value['books'][name]['pages'] = value['books'][name]['characterPages'] = pages
    if lost or favorite_unmoved or enabled and control == 'return-child-cancel':
        value['books']['front']['container'] = 'root'
        for entry in value['items']:
            if entry['id'] == ids['front']['id']: entry['container'] = 'root'
    value['volume'] = ids['initialVolume'] if lost and not enabled else ids['targetVolume']
    if not device_only(ids['control']):
        value['hands']['primary'] = False if lost and not enabled else ids['pen']['id']
    return value


_NONFINITE_TAG = '__queueNonfiniteNumber'


_DIAGNOSTIC_DURATIONS = frozenset(('duration', 'durationBefore', 'durationAfter', 'effectiveDuration'))


def _nonfinite_tag(value):
    return (isinstance(value, dict) and set(value) == {_NONFINITE_TAG}
            and value[_NONFINITE_TAG] in ('nan', '+inf', '-inf'))


def _nonfinite_locations(value, path=()):
    if isinstance(value, dict):
        if _NONFINITE_TAG in value:
            yield path, value
        else:
            for key, entry in value.items():
                yield from _nonfinite_locations(entry, path + (key,))
    elif isinstance(value, list):
        for index, entry in enumerate(value):
            yield from _nonfinite_locations(entry, path + (index,))


def _unstarted_admission_diagnostic(record, row, ids, enabled):
    """A duration observation grants no execution or timing authority."""
    debt, ui = row.get('blockedReturn'), row.get('failureUI')
    capacity, boundary = row.get('capacity'), row.get('boundary')
    if not enabled or not all(isinstance(value, dict) for value in (debt, ui, capacity, boundary)):
        return False
    if (record.get('type') != 'ISInventoryTransferAction' or record.get('role') != 'return'
            or record.get('item') != ids['front']['id'] or record.get('nativeSource') is not True
            or record.get('started') is not False or record.get('progress') is not False
            or record.get('sequence') in row.get('starts', [])
            or record.get('finishes') != [] or record.get('receipts') != []
            or any(record.get(key) is not None for key in ('startedAt', 'performedAt', 'transactionDuration'))
            or record.get('transaction') not in (None, False, 0)
            or record.get('transactionDone') not in (None, False) or record.get('transactionRejected') not in (None, False)
            or debt.get('reason') != 'admission' or debt.get('state') != 'blocked' or not debt.get('id')
            or debt.get('itemId') != ids['front']['id'] or debt.get('itemType') != ids['front']['type']
            or row.get('returnSucceeded') is not False or ui.get('id') != debt.get('id')
            or ui.get('itemId') != ids['front']['id']
            or any(ui.get(key) is not True for key in ('visible', 'idle', 'bookRoot', 'pressCaptured', 'cleared', 'bookRetained'))):
        return False
    if (not isinstance(record.get('nativeRef'), str) or not record['nativeRef']
            or not _number(record.get('allocatedAt')) or not _number(capacity.get('at')) or not _number(boundary.get('at'))
            or not boundary['at'] <= capacity['at'] <= record['allocatedAt']
            or capacity.get('itemId') != ids['front']['id'] or capacity.get('itemType') != ids['front']['type']
            or capacity.get('after') != 0 or capacity.get('roomAfter') is not False
            or record.get('sequence') in [member.get('sequence') for member in boundary.get('queue', [])]
            or record.get('token') == boundary.get('token')):
        return False
    for where in ('client', 'server'):
        book = row.get(where, {}).get('books', {}).get('front', {})
        if book.get('id') != ids['front']['id'] or book.get('type') != ids['front']['type'] or book.get('container') != 'root':
            return False
    return True


def _nonfinite_case_errors(row, ids, enabled):
    errors, allowed = [], set()
    for index, record in enumerate(row.get('records', [])):
        eligible = _unstarted_admission_diagnostic(record, row, ids, enabled)
        for field in _DIAGNOSTIC_DURATIONS | {'transactionDuration'}:
            if field not in record:
                continue
            value = record[field]
            if _nonfinite_tag(value) and eligible and field in _DIAGNOSTIC_DURATIONS:
                allowed.add(('records', index, field))
            elif not _number(value):
                errors.append('Nonfinite/malformed native timing outside exact unstarted admission failure: ' + str(index) + '/' + field)
    for path, value in _nonfinite_locations(row):
        if path not in allowed or not _nonfinite_tag(value):
            errors.append('Nonfinite/malformed diagnostic outside allowed unstarted transfer duration: ' + '/'.join(map(str, path)))
    return errors


def native_request_errors(row, case, selection, ids):
    """Local request evidence never substitutes for the independent effect audit."""
    if selection.get('options', {}).get('require_native_requests') is not True:
        return []
    errors = []
    source, control_name = case.split('.', 1)
    negative = (selection['mode'] == 'native' or selection['kind'] != 'mp'
                or source == 'root' or base_control(control_name) == 'return-child-cancel')
    failed = capacity_case(control_name)
    candidates = [r for r in row.get('records', []) if r.get('role') == ('front' if source == 'root' else 'return')]
    if not candidates:
        return ['Missing explicit native request positive/negative observation target']
    positive = False
    phases = {'pending', 'started', 'perform-begin', 'perform-finish', 'terminal'}
    sample_fields = {'case', 'sequence', 'actor', 'item', 'itemType', 'token', 'actionRef',
                     'nativeRef', 'point', 'at', 'current', 'transaction', 'observation', 'watchPending'}
    state_fields = {'phase', 'boundary', 'sourceExact', 'ambiguous', 'paired', 'nativeHandle',
                    'wireAmbiguous', 'transaction', 'id', 'fullType', 'currentHandle'}
    def transaction(value):
        return _number(value) and value == int(value) and -128 <= value <= 127 and value != 0
    for record in candidates:
        samples = record.get('requestStates')
        if not isinstance(samples, list) or not 2 <= len(samples) <= 16:
            errors.append('Missing bounded native request observation history'); continue
        points, seen, anchored, paired, last_at, request_id = set(), set(), False, False, -1, None
        submitted_binding = None
        for sample in samples:
            if not isinstance(sample, dict) or set(sample) != sample_fields:
                errors.append('Malformed native request observation'); continue
            point, at = sample.get('point'), sample.get('at')
            value, token, native_ref = sample['transaction'], sample['token'], sample['nativeRef']
            if (value is not False and not (_number(value) and value == int(value) and -128 <= value <= 127)
                    or token is not False and not (_number(token) and token == int(token) and token > 0)
                    or native_ref is not False and not _same_action(native_ref, record.get('nativeRef'))):
                errors.append('Malformed scalar native request cursor/token/native identity'); continue

            if (sample.get('case') != case or sample.get('sequence') != record.get('sequence')
                    or type(sample.get('sequence')) is not int or not _number(sample.get('actor')) or sample.get('actor') != ids['actor']
                    or not _number(sample.get('item')) or sample.get('item') != ids['front']['id'] or sample.get('itemType') != ids['front']['type']
                    or (type(sample.get('token')) is bool) != (type(record.get('token')) is bool)
                    or sample.get('token') != record.get('token') or not _same_action(sample.get('actionRef'), record.get('actionRef'))
                    or point not in phases or not _number(at) or at < last_at
                    or type(sample.get('current')) is not bool or type(sample.get('watchPending')) is not bool):
                errors.append('Native request case/actor/item/token/action/time binding differs'); continue
            last_at = at; points.add(point)
            key = copy.deepcopy(sample); key.pop('at', None)
            key['actionRef'] = _action_identity(key.get('actionRef'))
            key['nativeRef'] = _action_identity(key.get('nativeRef')) if key.get('nativeRef') else False
            try: signature = json.dumps(key, sort_keys=True, allow_nan=False)
            except (ValueError, TypeError):
                errors.append('Non-scalar native request evidence'); continue
            if signature in seen: errors.append('Duplicate native request transition')
            seen.add(signature)
            state = sample.get('observation')
            if state is False:
                continue
            if negative:
                errors.append('Private request state appeared on an absent-owner control'); continue
            if (not isinstance(state, dict) or set(state) - state_fields
                    or any(type(v) not in (str, int, float, bool) for v in state.values())
                    or state.get('phase') not in ('before', 'submitted', 'failed') or state.get('boundary') != 'start'
                    or not _number(state.get('id')) or state.get('id') != ids['front']['id'] or state.get('fullType') != ids['front']['type']
                    or any(type(state.get(k)) is not bool for k in ('sourceExact', 'paired', 'nativeHandle', 'wireAmbiguous', 'currentHandle'))
                    or 'ambiguous' in state and type(state['ambiguous']) is not bool
                    or not _same_action(sample.get('nativeRef'), record.get('nativeRef'))):
                errors.append('Malformed or foreign private native request state'); continue
            if state['phase'] == 'submitted':
                binding = tuple(state.get(k) for k in ('boundary', 'sourceExact', 'id', 'fullType', 'nativeHandle', 'ambiguous', 'transaction'))
                if submitted_binding is not None and binding != submitted_binding:
                    errors.append('Contradictory singleton submitted request history')
                submitted_binding = binding
            value = state.get('transaction')
            if value is not None and value != 0 and not transaction(value):
                errors.append('Native request transaction is not a signed nonzero byte'); continue
            if transaction(value):
                if request_id is not None and value != request_id:
                    errors.append('Singleton native request changed transaction')
                request_id = value
                if value != record.get('transaction'):
                    errors.append('Native request transaction differs from native transfer record')
                if sample.get('transaction') != value and not (point in ('perform-finish', 'terminal') and sample.get('transaction') == 0):
                    errors.append('Native request transaction differs from current/historical cursor')
            exact = (state.get('phase') == 'submitted' and state.get('sourceExact') is True
                     and state.get('nativeHandle') is True and state.get('wireAmbiguous') is False
                     and state.get('ambiguous') is False and transaction(value))
            if exact and state.get('currentHandle') is True and sample.get('current') is True and state.get('paired') is False:
                anchored = True
            if state.get('paired') is True:
                # Pairing links an attempt, including a stopped/rejected attempt;
                # it never asserts that a perform succeeded or an item arrived.
                debt = row.get('blockedReturn')
                rejected_stop = (failed and point == 'terminal' and row.get('returnSucceeded') is False
                    and isinstance(debt, dict) and debt.get('reason') == 'server' and debt.get('state') == 'blocked'
                    and debt.get('itemId') == ids['front']['id'] and debt.get('itemType') == ids['front']['type']
                    and row.get('server', {}).get('books', {}).get('front', {}).get('container') == 'root')
                if not exact or not anchored or (not paired and point != 'perform-finish' and not rejected_stop):
                    errors.append('Paired native request lacks its prior exact current owner or supported terminal attempt')
                else: paired = True
            elif paired:
                errors.append('Paired singleton request reverted to unpaired evidence')
        if not {'pending', 'terminal'} <= points:
            errors.append('Native request pending/terminal absence controls missing')
        if not negative and not failed and record.get('started') is True:
            if not anchored or not paired:
                errors.append('Started earned return lacks exact native request capture and pairing')
            else: positive = True
    if not negative and not failed and not positive:
        errors.append('No qualified singleton earned-return native request was observed')
    return errors


def native_transfer_stop_errors(row, case, selection, ids):
    requests = selection.get('options', {}).get('require_native_requests') is True
    errors, rejected = [], False
    entry_fields = {'case', 'sequence', 'actor', 'item', 'itemType', 'actionRef', 'nativeRef',
                    'transaction', 'at', 'point', 'current', 'nativePresent', 'endpointsExact', 'nativeSource',
                    'done', 'rejected', 'observation', 'guarded'}
    exit_fields = {'case', 'sequence', 'actor', 'item', 'itemType', 'actionRef', 'nativeRef',
                   'transaction', 'at', 'point', 'returned', 'sameNative'}
    for record in row.get('records', []):
        entry, returned = record.get('nativeStopEntry'), record.get('nativeStopReturned')
        if entry is None and returned is None:
            continue
        if (selection['kind'] != 'mp' or record.get('role') not in ('pickup', 'return')
                or not isinstance(entry, dict) or set(entry) != entry_fields
                or not isinstance(returned, dict) or set(returned) != exit_fields):
            errors.append('Missing paired exact native transfer stop boundaries'); continue
        for value in (entry, returned):
            if (value['case'] != case or type(value['sequence']) is not int or value['sequence'] != record.get('sequence')
                    or not _number(value['actor']) or value['actor'] != ids['actor']
                    or not _number(value['item']) or value['item'] != ids['front']['id'] or value['itemType'] != ids['front']['type']
                    or not _same_action(value['actionRef'], record.get('actionRef'))
                    or not _same_action(value['nativeRef'], record.get('nativeRef'))
                    or not _number(value['at'])):
                errors.append('Native transfer stop case/actor/item/action binding differs')
        tx = entry['transaction']
        if (not _number(tx) or tx != int(tx) or tx == 0 or not -128 <= tx <= 127 or tx != record.get('transaction')
                or entry['point'] != 'entry' or returned['point'] != 'returned'
                or any(entry[k] is not True for k in ('current', 'nativePresent', 'endpointsExact', 'nativeSource'))
                or type(entry['done']) is not bool or type(entry['rejected']) is not bool or type(entry['guarded']) is not bool
                or returned['returned'] is not True or returned['sameNative'] is not True
                or not _number(returned['transaction']) or returned['transaction'] != (0 if entry['guarded'] else tx)
                or not _number(entry['at']) or not _number(returned['at']) or entry['at'] > returned['at']
                or not _number(record.get('startedAt')) or entry['at'] < record['startedAt']
                or not _number(row.get('finishedAt')) or returned['at'] > row['finishedAt']
                or record.get('transactionDone') is not entry['done'] or record.get('transactionRejected') is not entry['rejected']):
            errors.append('Native stop is not the live unchanged transaction before cleanup')
        state = entry['observation']
        if selection['mode'] == 'native':
            if entry['guarded'] is not False or returned['transaction'] != tx:
                errors.append('Native stop control used guarded Toolkit cleanup')
            if state is not False: errors.append('Native stop control acquired a private request owner')
        elif record.get('role') == 'return':
            if entry['guarded'] is not True:
                errors.append('Toolkit return stop lost its guarded native cleanup')
            if not requests:
                if state is not False: errors.append('Disabled request diagnostics claimed a private request owner')
            elif (not isinstance(state, dict) or set(state) != {'phase', 'boundary', 'sourceExact', 'ambiguous', 'paired',
                    'nativeHandle', 'wireAmbiguous', 'transaction', 'id', 'fullType', 'currentHandle'}
                    or state.get('phase') != 'submitted' or state.get('boundary') != 'start'
                    or any(state.get(k) is not True for k in ('sourceExact', 'nativeHandle', 'currentHandle'))
                    or any(state.get(k) is not False for k in ('wireAmbiguous', 'ambiguous', 'paired'))
                    or not _number(state.get('transaction')) or state['transaction'] != tx
                    or not _number(state.get('id')) or state['id'] != ids['front']['id'] or state.get('fullType') != ids['front']['type']):
                errors.append('Native stop lacks its unreused exact current request object')
        elif state is not False:
            errors.append('Pickup stop acquired an earned-return request owner')
        if record.get('role') == 'return' and entry['rejected'] is True and entry['done'] is False:
            rejected = True
    if selection['kind'] == 'mp' and capacity_case(case.split('.', 1)[1]) and not rejected:
        errors.append('Capacity loss lacks native rejection before transaction removal')
    return errors


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


def performance_errors(value, case, enabled, probe=False, precise=False):
    errors = []
    timer, coarse = ('System.nanoTime', False) if precise else ('getTimestampMs', True)
    if (not isinstance(value, dict) or value.get('case') != case or value.get('timer') != timer
            or value.get('units') != 'ms' or value.get('coarse') is not coarse or value.get('readOnly') is not True
            or value.get('queueEnabled') is not enabled or type(value.get('queueCount')) is not int or not 1 <= value['queueCount'] <= 32
            or value.get('warmup') != 3 or value.get('samples') != 20 or not isinstance(value.get('limits'), str)):
        return ['Missing bounded read-only performance evidence for the selected clock']
    if precise:
        errors.extend(clock_errors(value.get('clockEvidence')))
    elif 'clockEvidence' in value:
        errors.append('Unbound monotonic clock evidence in a coarse-clock bank')
    modern = any(k in value for k in ASSESSMENT_POLICY)
    if modern and any(value.get(k) != v for k, v in ASSESSMENT_POLICY.items()):
        errors.append('Measurements cannot assert design acceptance or rejection')
    if modern and 'budgetBasis' in value:
        errors.append('Current observations must not restore a numerical acceptance gate')
    scoped = modern or precise or any(k in value for k in PERFORMANCE_SCOPE)
    if not modern and (scoped or 'budgetBasis' in value) and value.get('budgetBasis') != 'initial-engineering-targets':
        errors.append('Historical timing-reference provenance differs')
    if scoped and (any(value.get(k) != v for k, v in PERFORMANCE_SCOPE.items())
                   or any(value.get(k) is not False for k in ('completeEditMeasured', 'frameLoadMeasured'))):
        errors.append('Isolated call timings cannot qualify complete edit or frame load')
    if value.get('completeEditQualified', False) is not False:
        errors.append('Isolated call bank claimed complete edit qualification')
    metrics = value.get('metrics', [])
    expected_names = ['evaluateMove', 'evaluateCancel', 'previewMove', 'previewCancel', 'panelUpdate']
    if not isinstance(metrics, list) or [m.get('name') for m in metrics if isinstance(m, dict)] != expected_names:
        return ['Missing/duplicate actual Policy/Panel timing entrypoints']
    for index, metric in enumerate(metrics):
        kind = 'authoritative' if index < 2 else 'advisory'
        scope = 'policy-decision-call' if index < 2 else 'policy-preview-call' if index < 4 else 'panel-update-only'
        if scoped and metric.get('workScope') != scope:
            errors.append('Timing entrypoint work scope differs: ' + expected_names[index])
        raw = metric.get('rawMs')
        legacy_reference = (2, 4) if index < 2 else (1, 2)
        if (metric.get('kind') != kind or not _number(metric.get('firstUseMs')) or metric['firstUseMs'] < 0
                or any(not _number(metric.get(k)) for k in ('p95Ms', 'p99Ms'))
                or not isinstance(raw, list) or len(raw) != 20 or any(not _number(v) or v < 0 for v in raw)
                ):
            errors.append('Malformed raw timings/warmup separation: ' + expected_names[index]); continue
        if modern:
            if any(k in metric for k in ('p95BudgetMs', 'p99BudgetMs', 'passed')):
                errors.append('Current measurement claimed a numerical pass/fail: ' + expected_names[index])
        elif (any(not _number(metric.get(k)) for k in ('p95BudgetMs', 'p99BudgetMs'))
                or (metric.get('p95BudgetMs'), metric.get('p99BudgetMs')) != legacy_reference):
            errors.append('Malformed historical reference fields: ' + expected_names[index])
        first, last = metric.get('firstDecision'), metric.get('lastDecision')
        if index < 4:
            valid_observations = all(isinstance(observation, dict) and set(observation) == {'allowed', 'reason', 'mode'}
                and type(observation.get('allowed')) is bool
                and (observation.get('reason') is False if observation.get('allowed') else isinstance(observation.get('reason'), str) and bool(observation['reason']))
                and (observation.get('mode') is False or isinstance(observation.get('mode'), str)) for observation in (first, last))
            if (not valid_observations or metric.get('decisionSamples') != 24 or metric.get('decisionStable') is not True
                    or first != last or metric.get('decisionClass') != ('allowed' if valid_observations and first['allowed'] else 'denied')):
                errors.append('Missing/unstable scalar decision observations: ' + expected_names[index])
            if not enabled and valid_observations and (first['allowed'] is not False or first['reason'] != 'unavailable'):
                errors.append('Queue-off decision is not its explicit unavailable denial baseline: ' + expected_names[index])
        elif (metric.get('decisionSamples') != 0 or metric.get('decisionStable') is not True
                or first is not False or last is not False or metric.get('decisionClass') != 'not-decision'):
            errors.append('Panel update incorrectly claims an edit decision')
        ordered = sorted(raw); p95, p99 = ordered[18], ordered[19]
        if metric.get('p95Ms') != p95 or metric.get('p99Ms') != p99:
            errors.append('Timing quantile differs from raw samples: ' + expected_names[index])
        # Preserve the integrity of old data without retaining its acceptance policy.
        if not modern and metric.get('passed') is not (p95 <= legacy_reference[0] and p99 <= legacy_reference[1]):
            errors.append('Historical numerical comparison differs from raw samples: ' + expected_names[index])
    actual_allowed = all(isinstance(metric.get('firstDecision'), dict) and metric['firstDecision'].get('allowed') is True
        and metric.get('decisionStable') is True and metric.get('decisionClass') == 'allowed' for metric in metrics[:2])
    historical_numerical_match = all(metric.get('passed') is True and metric.get('decisionStable') is True for metric in metrics)
    expected_claim = False if modern else enabled and actual_allowed and historical_numerical_match
    if (value.get('pathClass') != ('toolkit-observed-decisions' if enabled else 'nativeoff-denial-baseline')
            or value.get('authorityAllowed') is not actual_allowed
            or value.get('positiveTimingClaim') is not expected_claim):
        errors.append('Timing path/positive claim differs from actual scalar decision observations')
    if probe and enabled and not actual_allowed:
        denied = ', '.join(metric.get('name', '?') + ':' + str(metric.get('firstDecision', {}).get('reason'))
                           for metric in metrics[:2] if isinstance(metric.get('firstDecision'), dict) and metric['firstDecision'].get('allowed') is not True)
        errors.append('Intended Toolkit32 authority edit denied: ' + denied)
    if not probe:
        bounded = value.get('probe32')
        errors.extend('32-member probe: ' + reason for reason in performance_errors(bounded, case, enabled, True, precise))
        if isinstance(bounded, dict):
            temporary = bounded.get('temporary')
            if (bounded.get('queueCount') != 32 or bounded.get('originalQueueCount') != value.get('queueCount')
                    or bounded.get('source') != 'fixture-temporary-native-constructors'
                    or bounded.get('constructor') != 'ISRadioAction.new' or bounded.get('nativeDuration') != 30
                    or any(bounded.get(k) is not True for k in ('nativeConstructorProof', 'restored', 'queueIdentityUnchanged', 'originalStateUnchanged'))
                    or not isinstance(temporary, list) or len(temporary) != 32 - value['queueCount']):
                errors.append('Missing exact32 private constructor-input/restoration evidence')
            elif (any(not isinstance(row, dict) or not isinstance(row.get('actionRef'), str)
                      or row.get('type') != 'ISRadioAction' or row.get('mode') != 'SetVolume' or row.get('duration') != 30
                      or row.get('nativeRef') is not False or row.get('started') is not False
                      or row.get('unexecuted') is not True or row.get('intentPublished') is not False for row in temporary)
                  or len({row.get('actionRef') for row in temporary}) != len(temporary)):
                errors.append('Temporary32 probe action executed, reused identity or published intent')
    return errors


def waiver_identity_errors(value, ids, boundary, retired):
    """Replica replacement is observed, never manufactured or required."""
    fields = {'schema', 'case', 'actor', 'source', 'actionRef', 'token', 'beforeAt', 'afterAt',
              'before', 'after', 'previewUnchanged', 'actualReplicaReplacement', 'previewCheckedAt', 'groupUnchangedAfterCommit'}
    if (not isinstance(value, dict) or set(value) != fields or type(value.get('schema')) is not int or value['schema'] != 1
            or value.get('case') != ids['case'] or value.get('actor') != ids['actor']
            or type(value.get('actor')) is not int or value.get('source') != ids['source']
            or not _same_action(value.get('actionRef'), retired.get('actionRef')) or value.get('token') != retired.get('token')
            or type(value.get('token')) is not int or value.get('previewUnchanged') is not True
            or value.get('groupUnchangedAfterCommit') is not True
            or type(value.get('actualReplicaReplacement')) is not bool
            or any(not _number(value.get(key)) for key in ('beforeAt', 'previewCheckedAt', 'afterAt'))
            or not value['beforeAt'] <= boundary.get('at', -1) <= value['previewCheckedAt'] <= value['afterAt'] <= boundary.get('ui', {}).get('acceptedAt', -1)):
        return ['Missing exact passive optional-return waiver identity boundary']
    errors = []
    for phase in ('before', 'after'):
        snapshot = value.get(phase)
        if (not isinstance(snapshot, dict) or set(snapshot) != {'requested', 'carried', 'rootMatches', 'directRootMatches', 'destinationMatches', 'sameReference'}
                or type(snapshot.get('sameReference')) is not bool
                or any(type(snapshot.get(key)) is not int for key in ('rootMatches', 'directRootMatches', 'destinationMatches'))
                or (snapshot['rootMatches'], snapshot['directRootMatches'], snapshot['destinationMatches']) != (1, 1, 0)):
            errors.append('Optional-return waiver lacks one direct carried replica and an empty destination'); continue
        for name in ('requested', 'carried'):
            item = snapshot.get(name)
            if (not isinstance(item, dict) or set(item) != {'ref', 'id', 'type', 'container'}
                    or not isinstance(item.get('ref'), str) or not item['ref']
                    or type(item.get('id')) is not int or item['id'] != ids['front']['id'] or item.get('type') != ids['front']['type']
                    or item.get('container') not in ('root', ids['source'], 'other', False)
                    or name == 'carried' and item.get('container') != 'root'):
                errors.append('Optional-return requested/carried exact replica identity differs')
        requested, carried = snapshot.get('requested'), snapshot.get('carried')
        if isinstance(requested, dict) and isinstance(carried, dict):
            if snapshot['sameReference'] is True and requested != carried:
                errors.append('Optional-return waiver same-reference summaries contradict the observed equality')
    before, after = value['before'], value['after']
    if isinstance(before, dict) and isinstance(after, dict):
        if value['actualReplicaReplacement'] is not (before.get('sameReference') is False):
            errors.append('Replica replacement claim differs from the passive pre-cancel observation')
        if (before.get('carried') != after.get('carried') or after.get('sameReference') is not True
                or after.get('requested') != after.get('carried')):
            errors.append('Committed waiver did not retain and bind the exact carried replica')
    return errors


def check_case(row, case, selection, prepared, authority_baseline, authority_final, admissions, boundaries, drains, acks, capacity_authority=None, stops=None):
    errors = []
    try:
        enabled = selection['mode'] == 'toolkit'
        source, original_control = case.split('.', 1)
        control = base_control(original_control); lost = capacity_case(original_control); favorite_unmoved = favorite_case(original_control) and selection['kind'] == 'sp'
        keep = enabled and control == 'return-child-cancel'
        device = device_only(original_control)
        demote = control == 'demote-reader'
        ids, boundary, records = row['ids'], row['boundary'], row['records']
        errors.extend(_nonfinite_case_errors(row, ids, enabled))
        errors.extend(native_request_errors(row, case, selection, ids))
        errors.extend(native_transfer_stop_errors(row, case, selection, ids))
        errors.extend(performance_errors(row.get('performance'), case, enabled, precise=selection.get('options', {}).get('precise_timing') is True))
        errors.extend(handler_timing_errors(boundary.get('ui'), selection.get('options', {}).get('precise_timing') is True, enabled))
        if isinstance(row.get('performance'), dict) and row['performance'].get('queueCount') != len(boundary.get('queue', [])):
            errors.append('Timing queue shape differs from the real edit boundary')
        spacing = row.get('tickSpacingMs')
        if not isinstance(spacing, list) or not spacing or len(spacing) > 60 or any(not _number(v) or v < 0 for v in spacing):
            errors.append('Missing bounded real tick-spacing observations')
        if row.get('status') != 'passed':
            errors.append('Fixture case failed: ' + str(row.get('reason')))
        if (row.get('id') != case or ids != prepared or ids.get('case') != case
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
        if ids['baseline']['books']['front'].get('container') != source or ids['baseline']['books']['front'].get('favorite') is not (source != 'world' or favorite_case(original_control)) or ids['baseline']['books']['tail'].get('favorite') is not True:
            errors.append('Exact favorite/native world-return eligibility or source container changed before producer')
        required = expected(ids, enabled, boundary, selection['kind'])
        if row.get('client') != required or row.get('server') != required:
            errors.append('Exact inventory/container conservation, paid pages, TV volume, Pen hand intent or untouched equipment/appearance failed')
        if lost:
            capacity = row.get('capacity', {})
            if (capacity != capacity_authority or capacity.get('case') != case or capacity.get('source') != source
                    or capacity.get('itemId') != ids['front']['id'] or capacity.get('itemType') != ids['front']['type']
                    or capacity.get('actor') != ids['actor'] or capacity.get('authority') is not True
                    or capacity.get('roomBefore') is not True or capacity.get('frontFavorite') is not (source != 'world')
                    or capacity.get('bookRoot') is not True or capacity.get('after') != 0 or capacity.get('roomAfter') is not False
                    or not _number(capacity.get('before')) or capacity['before'] <= 0
                    or not _number(capacity.get('requestedAt')) or not _number(capacity.get('at'))
                    or not boundary.get('at', float('inf')) <= capacity['requestedAt'] <= capacity['at']
                    or row.get('returnSucceeded') is not False):
                errors.append('Missing exact authority capacity loss after the accepted edit/native control boundary')
        if lost or favorite_unmoved:
            if row.get('returnSucceeded') is not False:
                errors.append('Failed return falsely claims actual movement')
            if enabled:
                debt, ui = row.get('blockedReturn', {}), row.get('failureUI', {})
                after = row.get('capacity', {}).get('at') if lost else boundary.get('at')
                if (not isinstance(debt, dict) or not debt.get('id') or debt.get('itemId') != ids['front']['id']
                        or debt.get('itemType') != ids['front']['type'] or debt.get('state') != 'blocked'
                        or debt.get('reason') not in ('admission', 'server', 'unmoved')
                        or favorite_unmoved and debt.get('reason') != 'unmoved'
                        or not isinstance(ui, dict) or ui.get('source') != 'ActionQueuePanel.KeepReturn'
                        or ui.get('input') != 'programmatic-press-callback' or ui.get('id') != debt.get('id')
                        or ui.get('itemId') != ids['front']['id'] or ui.get('count') != 1
                        or any(ui.get(k) is not True for k in ('visible', 'idle', 'bookRoot', 'pressCaptured', 'cleared', 'bookRetained'))
                        or not _number(ui.get('at')) or not _number(after) or ui['at'] < after):
                    errors.append('Failed return was not retained visibly with exact identity and explicitly kept through the real idle footer')
                if lost and (capacity.get('acceptedAt') != boundary.get('ui', {}).get('acceptedAt')
                        or not _number(capacity.get('acceptedAt')) or capacity['acceptedAt'] > capacity['requestedAt']):
                    errors.append('Capacity intervention preceded exact accepted gesture')
            elif (row.get('blockedReturn') is not False or row.get('failureUI') is not False or row.get('nativeDebtAbsent') is not True
                    or lost and capacity.get('acceptedAt') is not False):
                errors.append('Queue-off failed return acquired editor debt/Keep UI')
        elif row.get('blockedReturn') not in (None, False) or row.get('failureUI') not in (None, False):
            errors.append('Successful normal return acquired failed-return debt')
        if not lost and row.get('capacity') not in (None, False):
            errors.append('Noncapacity case acquired a capacity intervention')
        if (len(admissions) != 1 or admissions[0].get('producer') != 'ISInventoryPaneContextMenu.onLiteratureItems/readItem'
                or admissions[0].get('volumeProducer') != 'RWMVolume.onVolumeChange'
                or admissions[0].get('equipProducer') != (False if device else 'ISInventoryPaneContextMenu.equipWeapon')
                or admissions[0].get('sourceBound') is not True or len(boundaries) != 1
                or boundaries[0] != dict({k: v for k, v in boundary.items() if k not in ('drained', 'drainedAt')}, drained=False)):
            errors.append('Missing unique actual native producers and raw UI boundary')
        if (len(drains) != 1 or drains[0] != dict(case=case, reader=boundary.get('reader'), native=boundary.get('native'),
                at=boundary.get('drainedAt'), oldNativeAbsent=True) or not _number(boundary.get('drainedAt'))
                or boundary['drainedAt'] < boundary.get('at', float('inf'))):
            errors.append('Exact old Java allocation removal receipt missing')
        admission = admissions[0].get('queue', []) if len(admissions) == 1 else []
        initial_roles = [r.get('role') for r in admission if r.get('role') != 'preparation']
        if initial_roles != ((['pickup', 'front', 'return'] if source != 'root' else ['front']) + (['volume', 'tail'] if device else ['equip', 'volume', 'tail'])):
            errors.append('Actual literature source pickup/read/return or independent producer chain differs')
        if enabled:
            front_tokens = [r.get('token') for r in admission if r.get('role') in ('pickup', 'front', 'return')]
            separate = [r.get('token') for r in admission if r.get('role') in ('equip', 'volume', 'tail')]
            if (not front_tokens or type(front_tokens[0]) is not int or len(set(front_tokens)) != 1
                    or any(type(t) is not int for t in separate) or len(set(separate + front_tokens[:1])) != (3 if device else 4)):
                errors.append('Native source operation lost pickup/read/return identity or independent tokens')
        if (boundary.get('requested') is not enabled or any(boundary.get(k) is not True for k in ('tailRetained', 'volumePending', 'drained'))
                or boundary.get('equipPending') is not (not device)
                or not _number(boundary.get('at')) or not _number(boundary.get('delta')) or not 0 < boundary['delta'] < 1
                or boundary['before']['books']['front']['pages'] != ids['front']['initial'] + 1
                or boundary['before']['books']['front']['characterPages'] != ids['front']['initial'] + 1
                or boundary['before']['books']['tail']['pages'] != ids['tail']['initial']):
            errors.append('Edit did not target one paid page, active read and untouched independent work')
        front = [r for r in records if r.get('role') == 'front']
        others = {name: [r for r in records if r.get('role') == name] for name in ('tail', 'equip', 'volume')}
        moving = enabled and (control.startswith('move-') or control == 'demote-reader')
        if len(front) != (2 if moving else 1) or any(len(v) != (0 if device and name == 'equip' else 1) for name, v in others.items()):
            return errors + ['Duplicate/missing exact native reader, Pen equip, volume or unrelated tail']
        original = front[0]; tail, volume = (others[n][0] for n in ('tail', 'volume')); equip = others['equip'][0] if not device else None
        if device and (row.get('equipSnapshot') is not False or any(r.get('type') in ('ISEquipWeaponAction', 'ISUnequipAction', 'ISEquipHeavyItem') for r in records + admission)):
            errors.append('Device-only variant acquired an equipment action or snapshot')
        if (not _same_action(original.get('actionRef'), boundary.get('reader')) or original.get('nativeRef') != boundary.get('native')
                or original.get('item') != ids['front']['id'] or original.get('started') is not True or original.get('progress') is not True
                or tail.get('item') != ids['tail']['id'] or not device and (equip.get('item') != ids['pen']['id']
                or equip.get('type') != 'ISEquipWeaponAction') or volume.get('type') != 'ISRadioAction'):
            errors.append('Exact active reader/independent native item identity differs')
        ui = boundary.get('ui')
        if enabled:
            if (not isinstance(ui, dict) or ui.get('source') != 'ActionQueuePanel.List'
                    or ui.get('input') != ('programmatic-drag' if moving else 'programmatic-press-release')
                    or any(ui.get(k) is not True for k in ('hitTested', 'pressCaptured', 'gestureCleared', 'accepted'))
                    or ui.get('feedback') is not False or ui.get('singleton') is not (source == 'root')
                    or ui.get('header') is not (device and demote or not demote and source != 'root' and control not in ('reader-child-cancel', 'return-child-cancel'))
                    or ui.get('decision', {}).get('reason') is not False or ui.get('decision', {}).get('source') != source):
                errors.append('Actual hit-tested Panel gesture, exact header/child/singleton mapping or decision denied')
            if ui.get('operation') != (volume.get('token') if demote else original.get('token')) or type(original.get('token')) is not int:
                errors.append('Real Panel operation identity missing')
            if keep:
                retired = [r for r in records if r.get('role') == 'return' and r.get('token') == original.get('token')]
                errors.extend(waiver_identity_errors(ui.get('waiverIdentity'), ids, boundary, retired[0] if len(retired) == 1 else {}))
                if (len(retired) != 1 or sum(r.get('role') == 'return' for r in records) != 1
                        or not _same_action(ui.get('target'), retired[0].get('actionRef'))
                        or any(ui.get(k) is not True for k in ('bodyContinues', 'returnAbsent', 'bookRoot'))
                        or ui.get('operationCancelled') is not False
                        or retired[0].get('started') is not False or retired[0].get('progress') is not False
                        or retired[0].get('finishes') != [] or retired[0].get('receipts') != []
                        or any(retired[0].get(k) is not None for k in ('nativeRef', 'performedAt', 'startedAt', 'allocatedAt'))
                        or retired[0].get('transaction') not in (None, False)):
                    errors.append('Optional return cross stopped the reader, ran the retired return or lost exact keep intent')
            if not keep and 'waiverIdentity' in ui:
                errors.append('Non-return-child control acquired optional-return waiver evidence')
            if moving and (ui.get('dragging') is not True or not _same_action(ui.get('movingAction'), (original if demote else equip if control == 'move-equip' else volume).get('actionRef'))
                    or ui.get('movingToken') != (original if demote else equip if control == 'move-equip' else volume).get('token') or not ui.get('movingAnchor')):
                errors.append('Move gesture never crossed the drag threshold')
        elif ui is not False or row.get('reset') is not False:
            errors.append('Queue-off natural control performed an edit/reset')
        if device and enabled:
            approach=next((r for r in boundary.get('queue',[]) if r.get('role')=='preparation'and r.get('type')=='ISQueueActionsAction'and r.get('token')==volume.get('token')), {})
            if (ui.get('commonActiveEdit') is not False or ui.get('dropAfter') is not demote
                    or not _same_action(ui.get('targetAction'),volume.get('actionRef') if demote else original.get('actionRef'))
                    or not _same_action(ui.get('target'),approach.get('actionRef') if demote else original.get('actionRef'))
                    or not _same_action(ui.get('movingAnchor'),original.get('actionRef') if demote else approach.get('actionRef'))):
                errors.append('Device-only actual gesture lost legacy authority, genuine volume-group anchor or requested direction')
        starts = row.get('starts', [])
        expected_roles = (['front', 'equip', 'front', 'volume', 'tail'] if control == 'move-equip' else
                          ['front', 'volume', 'front', 'equip', 'tail']) if moving else ['front'] if lost and not enabled else ['front', 'equip', 'volume', 'tail']
        if device: expected_roles = [role for role in expected_roles if role != 'equip']
        by_sequence = {r.get('sequence'): r for r in records}
        if len(by_sequence) != len(records) or [by_sequence.get(i, {}).get('role') for i in starts if by_sequence.get(i, {}).get('role') in ('front', 'equip', 'volume', 'tail')] != expected_roles:
            errors.append('Pen/volume/read start order differs from the actual requested priority direction')
        expected_started = {r.get('sequence') for r in records if r.get('started') and r.get('role') in ('front', 'equip', 'volume', 'tail')}
        observed_started = [i for i in starts if by_sequence.get(i, {}).get('role') in ('front', 'equip', 'volume', 'tail')]
        if set(observed_started) != expected_started or len(observed_started) != len(expected_started):
            errors.append('Native started flags and exact start sequence disagree')
        if moving:
            resumed, receipt = front[1], row.get('resume', {})
            if (not isinstance(receipt, dict) or not _same_action(receipt.get('oldAction'), original.get('actionRef')) or not _same_action(receipt.get('newAction'), resumed.get('actionRef'))
                    or receipt.get('oldNative') != original.get('nativeRef') or receipt.get('newNative') != resumed.get('nativeRef')
                    or _same_action(receipt.get('newAction'), receipt.get('oldAction')) or receipt.get('newNative') == receipt.get('oldNative')
                    or receipt.get('oldNativeAbsent') is not True or receipt.get('item') != ids['front']['id']
                    or receipt.get('token') != original.get('token') or resumed.get('token') != original.get('token')
                    or receipt.get('startPage') != boundary['before']['books']['front']['pages']
                    or receipt.get('pages') != receipt.get('startPage') or resumed.get('progress') is not True):
                errors.append('Priority edit failed native stop/drain, fresh same-item/token reader or saved page resume')
        elif row.get('resume') is not False:
            errors.append('Unexpected fresh read after cancellation/natural control')
        for record in records:
            errors.extend(_record_errors(record, selection['kind'], case, ids['actor'], acks, lost))
        returns = [r for r in records if r.get('role') == 'return']
        if favorite_unmoved and not any(r.get('item') == ids['front']['id'] and _number(r.get('performedAt'))
                and [c.get('phase') for c in r.get('finishes', [])] == ['perform', 'complete']
                and all(c.get('succeeded') is True for c in r['finishes']) for r in returns):
            errors.append('Favorite refusal lacks actual source-bound successful callbacks plus exact unmoved final item')
        if lost and enabled:
            reason = row.get('blockedReturn', {}).get('reason')
            attempted = [r for r in returns if r.get('item') == ids['front']['id']]
            if reason == 'server' and not any(r.get('transactionRejected') is True for r in attempted):
                errors.append('Server debt lacks exact rejected native transfer')
            if reason == 'admission' and any(r.get('started') for r in attempted):
                errors.append('Admission debt was claimed after starting a native return')
            if reason == 'unmoved' and not any(_number(r.get('performedAt')) for r in attempted):
                errors.append('Unmoved debt lacks actual native return execution')
        gaps = row.get('replicaGaps')
        if not isinstance(gaps, list):
            errors.append('Missing exact replica convergence evidence')
        else:
            for gap in gaps:
                if not isinstance(gap, dict):
                    errors.append('Malformed exact replica gap'); continue
                diagnostic = gap.get('diagnostic', {})
                missing, mismatch = diagnostic.get('missing', {}), diagnostic.get('mismatch', {})
                if (diagnostic.get('case') != case or diagnostic.get('actor') != ids['actor']
                        or missing.get('front') is not True or any(value for name, value in missing.items() if name != 'front')
                        or any(mismatch.values()) or diagnostic.get('counts', {}).get('front') != dict(root=0, world=0)):
                    errors.append('Replica wait relaxed a scene/unrelated/exact ID invariant')
                record = next((r for r in records if r.get('sequence') == gap.get('sequence')), {})
                if (selection['kind'] != 'mp' or gap.get('case') != case or gap.get('actor') != ids['actor']
                        or gap.get('itemId') != ids['front']['id'] or gap.get('itemType') != ids['front']['type']
                        or gap.get('source') != source or gap.get('role') not in ('pickup', 'return')
                        or record.get('role') != gap.get('role') or record.get('item') != ids['front']['id']
                        or gap.get('actionRef') != record.get('actionRef') or gap.get('nativeRef') != record.get('nativeRef')
                        or gap.get('transaction') != record.get('transaction') or record.get('transactionDone') is not True
                        or record.get('transactionRejected') is not False or record.get('progress') is not True or not _number(record.get('performedAt'))
                        or gap.get('resolved') is not True or not all(_number(gap.get(k)) for k in ('startedAt', 'deadlineAt', 'resolvedAt'))
                        or gap.get('deadlineAt') != gap.get('startedAt', 0) + 2000
                        or not gap.get('startedAt', float('inf')) <= gap.get('resolvedAt', 0) <= gap.get('deadlineAt', 0)):
                    errors.append('Uncorrelated/unresolved/stale exact native transfer replica gap')
        interrupted = enabled and not keep
        if interrupted:
            stop, removal = original.get('stopReturned'), original.get('stoppedRemoval')
            checkpoint = boundary.get('nativeCheckpoint', {})
            if (not isinstance(stop, dict) or stops != [stop]
                    or not _same_action(stop.get('actionRef'), boundary.get('reader'))
                    or stop.get('case') != case or stop.get('nativeRef') != boundary.get('native')
                    or stop.get('item') != ids['front']['id'] or stop.get('pages') != boundary['before']['books']['front']['pages']
                    or any(stop.get(k) is not True for k in ('returned', 'queueOwned', 'nativePresent', 'bridgeStopped', 'nativeSource'))
                    or any(stop.get(k) is not False for k in ('finished', 'forceComplete'))
                    or any(checkpoint.get(k) is not False for k in ('finished', 'forceComplete'))
                    or not _number(stop.get('at')) or not boundary.get('ui', {}).get('acceptedAt', float('inf')) <= stop['at'] <= boundary.get('drainedAt', 0)):
                errors.append('Exact source-bound native stop return/bridge receipt missing or inconsistent')
            if (not isinstance(removal, dict) or not _same_action(removal.get('actionRef'), boundary.get('reader'))
                    or removal.get('nativeRef') != boundary.get('native')
                    or removal.get('item') != ids['front']['id'] or removal.get('pages') != boundary['before']['books']['front']['pages']
                    or any(removal.get(k) is not True for k in ('sameNative', 'queueAbsent', 'nativeAbsent'))
                    or any(removal.get(k) is not False for k in ('finished', 'forceComplete'))
                    or not _number(removal.get('at')) or not _number(row.get('finishedAt'))
                    or not boundary.get('drainedAt', float('inf')) <= removal['at'] <= row['finishedAt']):
                errors.append('Exact unfinished stopped reader removal from Lua and native queues missing')
            if original.get('performedAt') is not None or original.get('finishes') != []:
                errors.append('Interrupted original reader performed/completed or has unexpected lifecycle callbacks')
        elif any(original.get(k) is not None for k in ('stopReturned', 'stoppedRemoval')) or stops:
            errors.append('Naturally finished reader acquired a stop receipt')
        if (not enabled or moving or keep) and not _number(front[-1].get('performedAt')):
            errors.append('Naturally finished/resumed reader never performed')
        if not (lost and not enabled) and row.get('tailSnapshot', {}).get('books', {}).get('front') != required['books']['front']:
            errors.append('Book return/paid page was not settled before independent tail')
        if not (lost and not enabled) and row.get('tailSnapshot', {}).get('hands') != required['hands']:
            errors.append('Explicit Pen equip intent did not survive before the unrelated tail')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        errors.append('Malformed book-controls evidence: ' + str(error))
    return errors


def performance_observations(rows):
    observations, handlers = [], []
    for row in rows:
        if not isinstance(row, dict):
            continue
        outer = row.get('performance')
        if not isinstance(outer, dict):
            continue
        for scope, bank in (('natural', outer), ('probe32', outer.get('probe32'))):
            if not isinstance(bank, dict) or not isinstance(bank.get('metrics'), list):
                continue
            for metric in bank['metrics']:
                if not isinstance(metric, dict):
                    continue
                raw = metric.get('rawMs')
                valid = isinstance(raw, list) and bool(raw) and all(_number(v) and v >= 0 for v in raw)
                entry = dict(case=row.get('id'), scope=scope, metric=metric.get('name'), queueCount=bank.get('queueCount'),
                             timer=bank.get('timer'), validSamples=valid)
                if valid:
                    ordered = sorted(raw)
                    entry.update(samples=len(raw), minMs=ordered[0], medianMs=ordered[(len(raw)-1)//2]/2 + ordered[len(raw)//2]/2, maxMs=ordered[-1])
                    for key in ('firstUseMs', 'p95Ms', 'p99Ms'):
                        if _number(metric.get(key)): entry[key] = metric[key]
                observations.append(entry)
        boundary = row.get('boundary')
        ui = boundary.get('ui') if isinstance(boundary, dict) else None
        if isinstance(ui, dict) and isinstance(ui.get('handlerTiming'), dict):
            handlers.append(dict(case=row.get('id'), measurement=ui['handlerTiming']))
    return dict(ASSESSMENT_POLICY, observations=observations, handlers=handlers,
                runtimeImpact='not-established', historicalThresholds='not-an-acceptance-criterion')


def native_binding_errors(value, extended=False):
    if not isinstance(value, dict):
        return ['Missing native binding-loop source/environment evidence']
    expected = dict(compatFactories=2, cartFactories=1, canonicalPairs=True, plainEnvironment=True,
                    debugDisabled=True, readOnly=True, scope='source-owned-upvalues-no-guard-calls')
    if extended:
        expected.update(policyFactories=2, radioFactories=1, canonicalIpairs=True, canonicalGetmetatable=True)
    if (value.get('error') or any(type(value.get(k)) is not type(v) or value.get(k) != v for k, v in expected.items())):
        return ['Native binding-loop source/environment evidence differs']
    return []


def _exact(value, wanted):
    if type(value) is not type(wanted): return False
    if isinstance(wanted, dict): return value.keys() == wanted.keys() and all(_exact(value[k], v) for k, v in wanted.items())
    if isinstance(wanted, list): return len(value) == len(wanted) and all(_exact(a, b) for a, b in zip(value, wanted))
    return value == wanted


def _exact_action_record(value, wanted, action_fields):
    """Exact record shape/scalars; compare only declared Lua action refs by class/address."""
    return (type(value) is dict and value.keys() == wanted.keys()
        and all(_same_action(value[key], expected) if key in action_fields else _exact(value[key], expected)
                for key, expected in wanted.items()))


def _exact_device_plan(value, wanted):
    if (type(value) is not dict or value.keys() != wanted.keys()
            or not _exact(value.get('kind'), wanted['kind']) or type(value.get('nodes')) is not list
            or len(value['nodes']) != len(wanted['nodes'])):
        return False
    for actual, expected in zip(value['nodes'], wanted['nodes']):
        if type(actual) is not dict or actual.keys() != expected.keys():
            return False
        for key, expected_field in expected.items():
            if key == 'action':
                if not _same_action(actual[key], expected_field): return False
            elif key == 'returnEffect':
                if not _exact_action_record(actual[key], expected_field, {'action'}): return False
            elif not _exact(actual[key], expected_field): return False
    return True


def _exact_device_observer(value, wanted):
    if type(value) is not dict or value.keys() != wanted.keys(): return False
    if not _exact({k: v for k, v in value.items() if k != 'projection'},
                  {k: v for k, v in wanted.items() if k != 'projection'}): return False
    actual, expected = value['projection'], wanted['projection']
    if expected is False: return actual is False
    if type(actual) is not dict or actual.keys() != expected.keys(): return False
    if not _exact_action_record({k: v for k, v in actual.items() if k != 'deferred'},
                               {k: v for k, v in expected.items() if k != 'deferred'}, {'blocker'}): return False
    return (type(actual['deferred']) is list and len(actual['deferred']) == 1
            and _exact_action_record(actual['deferred'][0], expected['deferred'][0], {'action'}))


def device_active_edit_errors(value, row, case, selection):
    """Qualify one deferred native phase without granting a complete common edit."""
    if not isinstance(value, dict):
        return ['Missing device-only active-edit observation receipt']
    errors = []
    enabled = selection['mode'] == 'toolkit'
    source = case.split('.', 1)[0]
    boundary, records = row.get('boundary', {}), row.get('records', [])
    volume = next((r for r in records if r.get('role') == 'volume'), {})
    original = next((r for r in records if r.get('role') == 'front'), {})
    tail = next((r for r in records if r.get('role') == 'tail'), {})
    returns = [r for r in records if r.get('role') == 'return']
    required = dict(schema=3 if enabled else 1, case=case, kind=selection['kind'], mode=selection['mode'], queueEnabled=enabled,
        scope='active-edit-device-only-deferred-native-phase-observation' if enabled else 'active-edit-device-only-preempt-observation', mutationAuthorized=False, permissionsMeasured=False,
        nativeStarted=True, nativeFinished=False, nativeForceComplete=False, qualifiedReturn=False,
        effect=False, nativeFacts=False, aliasFacts=False, readOnly=True, uiUnchanged=True, passed=True, failure=False, source=source)
    if any(type(value.get(k)) is not type(v) or value[k] != v for k, v in required.items()):
        errors.append('Device-only active-edit checkpoint/read-only contract differs')
    if (not _same_action(value.get('current'), boundary.get('reader'))
            or not _same_action(value.get('currentNative'), boundary.get('native'))
            or not _same_action(value.get('current'), original.get('actionRef'))
            or not _same_action(value.get('currentNative'), original.get('nativeRef'))
            or original.get('started') is not True or boundary.get('nativeCheckpoint') != dict(finished=False, forceComplete=False)
            or type(value.get('currentLuaStartedPresent')) is not bool or type(value.get('currentLuaStarted')) is not bool
            or not value.get('currentLuaStartedPresent') and value.get('currentLuaStarted') is not False
            or not isinstance(value.get('liveItem'), str) or not value['liveItem']):
        errors.append('Device-only genuine reader/native identity differs')
    demote = base_control(case.split('.', 1)[1]) == 'demote-reader'
    intent = dict(kind='move', action=boundary.get('reader') if demote else volume.get('actionRef'),
                  target=volume.get('actionRef') if demote else boundary.get('reader'), after=demote)
    if not _exact_action_record(value.get('intent'), intent, {'action', 'target'}):
        errors.append('Device-only observation did not use the actual volume-to-reader move intent')
    decision = dict(entrypoint='Policy.evaluateMove', allowed=enabled, reason=False if enabled else 'unavailable', whole=False, commonActiveEdit=False)
    if not _exact(value.get('existingDecision'), decision):
        errors.append('Device-only actual move must retain legacy authority')
    observer = value.get('observer')
    if not enabled:
        wanted = dict(status='unhandled', reason='unavailable', allowedAbsent=True, projection=False, returns=0, unresolved=0)
        if not _exact_device_observer(observer, wanted): errors.append('Device-only queue-off observer acquired a projection')
    if enabled:
        approach_rows=[(index,r) for index,r in enumerate(boundary.get('queue',[]),1)
            if r.get('role')=='preparation'and r.get('type')=='ISQueueActionsAction'and r.get('token')==volume.get('token')]
        approach_index,queued_approach=approach_rows[0] if len(approach_rows)==1 else (None,{})
        preparations=[r for r in records if r.get('role')=='preparation'and r.get('type')=='ISQueueActionsAction'
            and r.get('token')==volume.get('token')and _same_action(r.get('actionRef'),queued_approach.get('actionRef'))]
        approach=preparations[0] if len(preparations)==1 else {}
        endpoints=queued_approach.get('approach',{})
        if not isinstance(endpoints,dict): endpoints={}
        actor,target=endpoints.get('actor'),endpoints.get('targetSquare')
        descriptor=dict(version=1,kind='deferred-spatial',actor=actor,targetSquare=target,
            invalidates='all-resources',routing='native',expansion='native',outcome='native')
        projection=dict(status='deferred',reason='edit_native_resolution',externalCapacity=True,allowedAbsent=True,
            blocker=approach.get('actionRef'),evaluatedPrefix=1,
            deferred=[dict(action=approach.get('actionRef'),index=2,descriptor=descriptor)])
        wanted=dict(status='observed',reason=False,allowedAbsent=True,projection=projection,returns=0,unresolved=0)
        if not _exact_device_observer(observer,wanted):
            errors.append('Device-only projection lost the exact deferred native obligation or acquired forecast/permission fields')
        ownership=dict(declared=True,owned=True,nativeConstructor=True,nativeResolver=True,ownedStart=True,actor=actor,targetSquare=target)
        if (len(preparations)!=1 or type(approach.get('token')) is not int or not _exact(approach.get('approach'),ownership)
                or not isinstance(actor,str)or not actor or not isinstance(target,str)or not target or actor==target
                or len(approach_rows)!=1 or queued_approach.get('type')!='ISQueueActionsAction'or queued_approach.get('role')!='preparation'
                or queued_approach.get('token')!=volume.get('token')or queued_approach.get('nativeRef')is not False
                or queued_approach.get('current')is not False or not _exact(queued_approach.get('approach'),ownership)):
            errors.append('Device-only native phase lacks the exact pending source-owned native volume approach record')
        boundary_members=[original,*returns,approach,volume,tail]
        actual_members=boundary.get('queue',[])
        if (type(actual_members)is not list or len(actual_members)!=len(boundary_members)
                or any(not _same_action(actual.get('actionRef'),expected.get('actionRef'))
                       or actual.get('role')!=expected.get('role')or actual.get('type')!=expected.get('type')
                       or not _exact(actual.get('token'),expected.get('token')) for actual,expected in zip(actual_members,boundary_members))):
            errors.append('Device-only observed plan omitted or changed a real pending queue member')
        if 'control' in value: errors.append('Device-only toolkit preempt mislabeled as a native control')
        nodes = [dict(kind='checkpoint', action=boundary.get('reader'), complete=True, capacity='unchanged'),
                 dict(kind='pending', action=approach.get('actionRef'), complete=False, capacity=False, deferred=descriptor),
                 dict(kind='pending', action=volume.get('actionRef'), complete=True, capacity='unchanged'),
                 dict(kind='resume', action=boundary.get('reader'), complete=True, capacity='unchanged')]
        prototype = value.get('prototype', {})
        for returning in returns:
            return_effect = dict(version=1, complete=True, capacity='external', domain='item', id=row.get('ids', {}).get('front', {}).get('id'),
                fullType=row.get('ids', {}).get('front', {}).get('type'), item=value.get('liveItem'), source=prototype.get('source') if isinstance(prototype, dict) else None,
                destination=prototype.get('destination') if isinstance(prototype, dict) else None, action=returning.get('actionRef'), synthetic=False,
                resources=1, requirements=1, effects=1, field='location')
            nodes.append(dict(kind='pending', action=returning.get('actionRef'), complete=True, capacity='external', returnEffect=return_effect))
        nodes.append(dict(kind='pending', action=tail.get('actionRef'), complete=True, capacity='unchanged'))
        if (not _exact_device_plan(value.get('plan'), dict(kind='preempt', nodes=nodes)) or len(returns) != int(source != 'root')
                or any(r.get('role') == 'equip' or r.get('type') in ('ISEquipWeaponAction', 'ISUnequipAction', 'ISEquipHeavyItem') for r in records)
                or boundary.get('ui', {}).get('commonActiveEdit') is not False):
            errors.append('Device-only plan lost exact native approach/volume order, introduced equipment or changed legacy authority')
        diagnostics=value.get('diagnostics')
        wanted_gaps=[]
        wanted_nodes=[dict(kind=node['kind'],action=node['action'],complete=node['complete'],
                           **({'deferred':node['deferred']} if 'deferred'in node else {})) for node in nodes]
        if (not isinstance(diagnostics,dict)or set(diagnostics)!={'contractGaps','nodes','projectionBlockerType','gapsTruncated','nodesTruncated'}
                or not _exact(diagnostics.get('contractGaps'),wanted_gaps)or diagnostics.get('projectionBlockerType')!='ISQueueActionsAction'
                or diagnostics.get('gapsTruncated')is not False or diagnostics.get('nodesTruncated')is not False
                or type(diagnostics.get('nodes'))is not list or len(diagnostics['nodes'])!=len(wanted_nodes)
                or any(not _exact_action_record(actual,expected,{'action'}) for actual,expected in zip(diagnostics.get('nodes',[]),wanted_nodes))):
            errors.append('Device-only diagnostics must identify one typed native phase, no contract gaps and complete remaining nodes')
    elif value.get('plan') is not False or value.get('control') != 'queue-disabled':
        errors.append('Device-only queue-disabled control acquired a transition plan')
    ledger = value.get('ledgerBefore')
    if not isinstance(ledger, dict) or ledger != value.get('ledgerAfter'):
        errors.append('Device-only private ledger changed or missing')
    else:
        loans = ledger.get('borrowings')
        borrowed = enabled and source != 'root'
        if (ledger.get('status') != ('observed' if enabled else 'unhandled') or not isinstance(loans, list)
                or len(loans) != int(borrowed) or type(ledger.get('earnedPreparations')) is not int
                or ledger['earnedPreparations'] < int(borrowed)):
            errors.append('Device-only genuine private loan/pickup evidence differs')
        if borrowed:
            prototype = value.get('prototype', {})
            if (not isinstance(prototype, dict) or len(returns) != 1 or not _same_action(prototype.get('action'), returns[0].get('actionRef'))
                    or prototype.get('pending') is not True or prototype.get('allowMissingItems') is not True
                    or prototype.get('item') != value.get('liveItem') or prototype.get('sameItemReference') is not True):
                errors.append('Device-only plan lost exact original pending native return prototype')
            loan = loans[0] if isinstance(loans, list) and len(loans) == 1 else {}
            book = row.get('ids', {}).get('front', {})
            if (loan.get('id') != book.get('id') or loan.get('fullType') != book.get('type')
                    or loan.get('state') != 'active' or loan.get('ambiguous') is not False
                    or loan.get('returning') is not False or loan.get('plannedReturn') is not False
                    or not isinstance(prototype, dict) or prototype.get('source') != loan.get('destination')
                    or prototype.get('destination') != loan.get('source') or loan.get('source') == loan.get('destination')
                    or not isinstance(loan.get('source'), str) or not loan['source']
                    or not isinstance(loan.get('destination'), str) or not loan['destination']
                    or not any(r.get('role') == 'pickup' and _number(r.get('performedAt')) for r in records)):
                errors.append('Device-only pending return lost original earned borrowing')
    bindings = value.get('sources', {})
    if not isinstance(bindings, dict) or any(bindings.get(k) != v for k, v in dict(observer='ActionQueuePolicy.lua', cleanup='ActionQueueSettlement.lua', bulk='BulkActions.lua', compat='ActionQueueCompat.lua', carts='ActionQueueCarts.lua').items()):
        errors.append('Device-only production source bindings missing')
    performance = value.get('performance')
    required_performance = dict(scope='paired-live-device-preempt-entrypoints', timer='System.nanoTime', units='ms', warmupPairs=1, pairs=3,
        sameLiveIntent=True, whole=False, firstUseScope='first-call-after-untimed-identity-ledger-and-native-facts-diagnostics',
        comparable=False, comparisonReason='deferred-native-phase-not-full-projection' if enabled else 'queue-disabled',
        observerProjectionStatus='deferred' if enabled else False, observerProjectionReason='edit_native_resolution' if enabled else False, timerOverhead='included-not-subtracted',
        sameOutputContract=False, completeEditMeasured=False, frameLoadMeasured=False, positiveTimingClaim=False, assessment='not-assessed')
    if (not isinstance(performance, dict) or set(performance) != set(required_performance) | {'baseline', 'observer', 'baselineFirstMs', 'observerFirstMs'}
            or any(type(performance.get(k)) is not type(v) or performance[k] != v for k, v in required_performance.items())):
        errors.append('Device-only timing scope or unsupported timing/permission claim differs')
    else:
        for key in ('baselineFirstMs', 'observerFirstMs'):
            if not _number(performance[key]) or performance[key] < 0: errors.append('Device-only first-use timing invalid')
        for key in ('baseline', 'observer'):
            timing = performance[key]
            samples = timing.get('samplesMs') if isinstance(timing, dict) else None
            if (not isinstance(samples, list) or len(samples) != 3 or any(not _number(v) or v < 0 for v in samples)
                    or set(timing) != {'samplesMs', 'samples', 'minMs', 'medianMs', 'maxMs', 'meanMs'} or type(timing.get('samples')) is not int or timing['samples'] != 3):
                errors.append('Device-only paired timing samples invalid'); continue
            wanted = dict(minMs=min(samples), medianMs=sorted(samples)[1], maxMs=max(samples), meanMs=sum(samples)/3)
            if any(not _number(timing.get(k)) or not math.isclose(timing[k], v, rel_tol=1e-9, abs_tol=1e-9) for k, v in wanted.items()):
                errors.append('Device-only paired timing distribution differs')
    return errors


def active_edit_errors(value, row, case, selection):
    """Qualify the opt-in return-effect layer, without assigning edit/frame rights."""
    if case in DEVICE_ONLY_CASES:
        return device_active_edit_errors(value, row, case, selection)
    errors = []
    enabled = selection['mode'] == 'toolkit'
    source = case.split('.', 1)[0]
    borrowed = enabled and source != 'root'
    if not isinstance(value, dict):
        return ['Missing active-edit observation receipt']
    expected = dict(schema=1, case=case, kind=selection['kind'], mode=selection['mode'],
                    queueEnabled=enabled, scope='active-edit-native-return-effect-observation',
                    mutationAuthorized=False, permissionsMeasured=False, nativeStarted=True, nativeFinished=False, nativeForceComplete=False,
                    qualifiedReturn=borrowed, readOnly=True, uiUnchanged=True,
                    passed=True)
    for key, wanted in expected.items():
        if type(value.get(key)) is not type(wanted) or value[key] != wanted:
            errors.append('Active-edit receipt differs: ' + key)
    # Older receipts used Lua's `ok and false or tostring(problem)`, encoding
    # a successful absent error as exactly 'nil'. Preserve only that success.
    if value.get('failure') is not False and not (value.get('passed') is True and value.get('failure') == 'nil'):
        errors.append('Active-edit receipt differs: failure')
    if (type(value.get('currentLuaStartedPresent')) is not bool or type(value.get('currentLuaStarted')) is not bool
            or value.get('currentLuaStartedPresent') is False and value.get('currentLuaStarted') is not False):
        errors.append('Active-edit optional Lua started diagnostics are inconsistent')
    boundary = row.get('boundary', {})
    current, native = value.get('current'), value.get('currentNative')
    checkpoint = boundary.get('nativeCheckpoint', {})
    records = row.get('records', [])
    front = next((r for r in records if r.get('role') == 'front' and _same_action(r.get('actionRef'), current)), {})
    if (not _same_action(current, boundary.get('reader')) or not _same_action(native, boundary.get('native'))
            or not _same_action(front.get('nativeRef'), native) or front.get('started') is not True
            or checkpoint.get('finished') is not False or checkpoint.get('forceComplete') is not False
            or value.get('source') != source or not isinstance(value.get('liveItem'), str) or not value['liveItem']):
        errors.append('Active-edit genuine current/native reader checkpoint differs')
    ids = row.get('ids', {})
    book = ids.get('front', {})
    ledger = value.get('ledgerBefore')
    after = value.get('ledgerAfter')
    if not isinstance(ledger, dict) or ledger != after:
        errors.append('Active-edit private ledger changed or is missing')
        ledger = {}
    loans = ledger.get('borrowings')
    if not isinstance(loans, list):
        errors.append('Active-edit borrowing evidence missing')
        loans = []
    if type(ledger.get('earnedPreparations')) is not int or ledger['earnedPreparations'] < 0:
        errors.append('Active-edit earned preparation count invalid')
    observed = value.get('observer')
    decision = value.get('existingDecision')
    if (not isinstance(decision, dict) or decision.get('entrypoint') != 'Policy.evaluateCancel'
            or type(decision.get('allowed')) is not bool or decision.get('whole') is not True
            or not (decision.get('reason') is False or isinstance(decision.get('reason'), str))):
        errors.append('Active-edit real whole-operation baseline missing')
        decision = {}
    if not enabled and decision.get('allowed') is not False:
        errors.append('Active-edit queue-disabled control acquired a Policy edit permission')
    if not isinstance(observed, dict):
        errors.append('Active-edit observer summary missing')
        observed = {}
    status = 'observed' if enabled else 'unhandled'
    if (observed.get('status') != status or observed.get('allowedAbsent') is not True or 'allowed' in observed
            or type(observed.get('returns')) is not int or observed['returns'] != int(borrowed)
            or type(observed.get('unresolved')) is not int or observed['unresolved'] < 0
            or not (observed.get('reason') is False or isinstance(observed.get('reason'), str))):
        errors.append('Active-edit observer result acquired rights or wrong virtual return')
    projection = observed.get('projection')
    if (enabled and not isinstance(projection, dict) or not enabled and projection is not False
            or borrowed and isinstance(projection, dict) and projection.get('externalCapacity') is not True):
        errors.append('Active-edit overall projection/capacity evidence missing or control acquired one')
    if projection is not False and (not isinstance(projection, dict)
            or projection.get('allowedAbsent') is not True or 'allowed' in projection or type(projection.get('externalCapacity')) is not bool
            or projection.get('status') not in ('allowed', 'denied', 'unhandled')
            or not (projection.get('reason') is False or isinstance(projection.get('reason'), str))
            or projection.get('status') != 'allowed' and not projection.get('reason')):
        errors.append('Active-edit overall projection lost its unknown reason or acquired rights')
    if enabled and (not isinstance(projection, dict) or projection.get('status') != 'unhandled' or projection.get('reason') != 'edit_unknown'):
        errors.append('Mixed equipment header observation lost its explicit unknown projection')
    bindings = value.get('sources', {})
    expected_sources = dict(observer='ActionQueuePolicy.lua', cleanup='ActionQueueSettlement.lua',
                           bulk='BulkActions.lua', compat='ActionQueueCompat.lua', carts='ActionQueueCarts.lua')
    if not isinstance(bindings, dict) or any(bindings.get(k) != v for k, v in expected_sources.items()):
        errors.append('Active-edit actual source wrapper evidence missing')
        bindings = {}
    if borrowed:
        facts, prototype, effect = (value.get(k) for k in ('nativeFacts', 'prototype', 'effect'))
        if not all(isinstance(v, dict) for v in (facts, prototype, effect)):
            errors.append('Active-edit borrowed return lacks native facts/prototype/typed effect')
        else:
            item, root, destination = facts.get('item'), facts.get('source'), facts.get('destination')
            if (facts.get('scope') != 'independent-native-value-probe' or type(facts.get('schema')) is not int
                    or facts['schema'] != 2 or not all(isinstance(v, str) and v for v in (item, root, destination))
                    or root == destination or item != value.get('liveItem') or facts.get('primaryKnown') is not True
                    or facts.get('primaryFullType') is not False):
                errors.append('Active-edit native schema2 item/endpoints or primary facts differ')
            owner_type = ids.get('bag', {}).get('type') if isinstance(ids.get('bag'), dict) else False
            if (facts.get('destinationOwnerFullType') != owner_type
                    or source == 'worn-bag' and (not isinstance(facts.get('destinationOwner'), str) or not facts['destinationOwner'])
                    or source == 'world' and facts.get('destinationOwner') is not False):
                errors.append('Active-edit native destination owner type differs')
            constructor, perform = bindings.get('transferConstructor'), bindings.get('transferPerform')
            # Diagnostic identities, not filename authority: the native probe,
            # earned private loan and typed effect above/below remain mandatory.
            # Carts.bindingSource/sourcesPinned qualifies this exact upstream pair.
            reviewed_sources = (
                constructor in ('CartTransferInterceptor.lua', 'ActionQueueCompat.lua', 'ISInventoryTransferAction.lua')
                and perform in ('ActionQueueCompat.lua', 'Proximity_ISInventoryTransferAction.lua', 'ISInventoryTransferAction.lua')
                or (constructor, perform) == ('TransferRestrictions.lua', 'VisualUpdateQueue.lua')
                and bindings.get('carts') == 'ActionQueueCarts.lua'
            )
            alias_facts = value.get('aliasFacts', False)
            same_member = prototype.get('sameMemberReference')
            alias_valid = False
            if same_member is False:
                expected_alias = dict(scope='independent-native-alias-probe', schema=2, item=item, source=root,
                                      destination=destination, aliasMember=prototype.get('member'), aliasResolution='native-root-id')
                alias_valid = (selection['kind'] == 'mp' and bindings.get('nativeAlias') is True
                    and isinstance(prototype.get('member'), str) and bool(prototype['member']) and prototype['member'] != item
                    and isinstance(alias_facts, dict) and set(alias_facts) == set(expected_alias)
                    and all(type(alias_facts.get(key)) is type(wanted) and alias_facts[key] == wanted
                            for key, wanted in expected_alias.items()))
                if not alias_valid:
                    errors.append('Active-edit detached member lacks exact native ID-resolution proof')
            elif same_member is not True or prototype.get('member') != item or alias_facts is not False:
                errors.append('Active-edit singleton member/reference proof differs')
            if (prototype.get('sameItemReference') is not True or not (same_member is True or alias_valid)
                    or prototype.get('item') != item or prototype.get('liveItem') != item
                    or prototype.get('itemId') != book.get('id') or prototype.get('itemType') != book.get('type')
                    or prototype.get('source') != root or prototype.get('destination') != destination
                    or prototype.get('allowMissingItems') is not True or prototype.get('pending') is not True
                    or not isinstance(prototype.get('action'), str) or not prototype['action']
                    or not any(r.get('role') == 'return' and _same_action(r.get('actionRef'), prototype['action']) for r in records)
                    or prototype.get('constructorSource') != bindings.get('transferConstructor')
                    or prototype.get('performSource') != bindings.get('transferPerform')
                    or prototype.get('stopSource') not in ('BulkActions.lua', 'ActionQueueCompat.lua', 'ISInventoryTransferAction.lua')
                    or not reviewed_sources):
                errors.append('Active-edit actual pending return prototype identity/wrappers differ')
            expected_effect = dict(version=1, complete=True, capacity='external', domain='item', id=book.get('id'),
                                   fullType=book.get('type'), item=item, source=root, destination=destination,
                                   actionAbsent=True, synthetic=True, resources=1, requirements=1, effects=1, field='location')
            if set(effect) != set(expected_effect) or any(type(effect.get(k)) is not type(v) or effect[k] != v for k, v in expected_effect.items()):
                errors.append('Active-edit typed return is not one exact external-capacity location effect')
            loan = loans[0] if len(loans) == 1 and isinstance(loans[0], dict) else {}
            # These are editLedger metadata snapshots: native borrowed producers
            # retain toolkitPickups. Fresh cleanup separately proves their coverage
            # before emitting the qualified location effect; it must not erase hints.
            if (ledger.get('status') != 'observed' or type(ledger.get('earnedPreparations')) is not int
                    or ledger['earnedPreparations'] <= 0 or ledger.get('legacyHints') is not True
                    or ledger.get('providersPresent') is not False or type(ledger.get('generation')) is not int
                    or ledger['generation'] < 0
                    or loan.get('id') != book.get('id') or loan.get('fullType') != book.get('type')
                    or loan.get('state') != 'active' or loan.get('ambiguous') is not False
                    or loan.get('returning') is not False or loan.get('plannedReturn') is not False
                    or loan.get('source') != destination or loan.get('destination') != root
                    or len(loans) != 1 or not any(r.get('role') == 'pickup' and _number(r.get('performedAt')) for r in records)):
                errors.append('Active-edit genuine native-earned exclusive private borrowing missing')
            owner = loan.get('sourceOwner')
            expected_owner = dict(id=ids['bag']['id'], fullType=ids['bag']['type']) if source == 'worn-bag' else False
            if owner != expected_owner:
                errors.append('Active-edit private source owner differs')
        if 'control' in value:
            errors.append('Active-edit qualified return mislabeled as a control')
    else:
        if value.get('aliasFacts', False) is not False:
            errors.append('Active-edit control acquired a native alias relation')
        control = 'no-loan' if enabled else 'queue-disabled'
        if (value.get('control') != control or any(value.get(k) is not False for k in ('effect', 'nativeFacts'))
                or enabled and (ledger.get('status') != 'observed' or loans or ledger.get('legacyHints') is not False
                                or value.get('prototype') is not False)):
            errors.append('Active-edit root/no-queue control acquired a return or private debt')
    performance = value.get('performance')
    if not isinstance(performance, dict):
        return errors + ['Active-edit paired real-entrypoint timing missing']
    comparable = borrowed and decision.get('allowed') is True and observed.get('status') == 'observed'
    reason = ('useful-return-effect-layer-and-existing-cancel-success' if comparable else
              value.get('control') or 'existing-cancel-denied-or-observer-unknown')
    required = dict(scope='paired-live-header-return-entrypoints', timer='System.nanoTime', units='ms', warmupPairs=1, pairs=3,
                    sameLiveIntent=True, whole=True, firstUseScope='first-call-after-untimed-identity-ledger-and-native-facts-diagnostics',
                    comparable=comparable, comparisonReason=reason, timerOverhead='included-not-subtracted',
                    sameOutputContract=False, completeEditMeasured=False, frameLoadMeasured=False,
                    positiveTimingClaim=False, assessment='not-assessed',
                    observerProjectionStatus=projection.get('status', False) if isinstance(projection, dict) else False,
                    observerProjectionReason=projection.get('reason', False) if isinstance(projection, dict) else False)
    if (set(performance) != set(required) | {'baseline', 'observer', 'baselineFirstMs', 'observerFirstMs'}
            or any(type(performance.get(k)) is not type(v) or performance[k] != v for k, v in required.items())):
        errors.append('Active-edit timing scope/comparability/projection or assessment claim differs')
    for key in ('baselineFirstMs', 'observerFirstMs'):
        if not _number(performance.get(key)) or performance[key] < 0:
            errors.append('Active-edit first-use timing invalid: ' + key)
    for role in ('baseline', 'observer'):
        timing = performance.get(role)
        if not isinstance(timing, dict):
            errors.append('Active-edit paired timing distribution missing: ' + role)
            continue
        values = timing.get('samplesMs')
        if (set(timing) != {'samplesMs', 'samples', 'minMs', 'medianMs', 'maxMs', 'meanMs'}
                or type(timing.get('samples')) is not int or timing['samples'] != 3 or not isinstance(values, list)
                or len(values) != 3 or any(not _number(v) or v < 0 for v in values)):
            errors.append('Active-edit paired samples invalid: ' + role)
            continue
        ordered = sorted(values)
        stats = dict(minMs=ordered[0], medianMs=ordered[1], maxMs=ordered[2], meanMs=sum(values) / 3)
        if any(not _number(timing.get(k)) or not math.isclose(timing[k], wanted, rel_tol=1e-9, abs_tol=1e-9)
               for k, wanted in stats.items()):
            errors.append('Active-edit timing distribution inconsistent: ' + role)
    return errors


def verify(root, selection, catalog):
    root = Path(root); issues, outcomes, rows = [], [], []
    try:
        validate(selection)
        cases = selected_cases(selection)
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [r for r in report.events(text) if r.get('suite') == 'book-controls']
        setup = [r for r in events if r.get('event') == 'setup']; rows = [r for r in events if r.get('event') == 'case']; final = [r for r in events if r.get('event') == 'complete']
        if (len(setup) != 1 or setup[0].get('cases') != cases
                or any(setup[0].get(k) is not True for k in ('nativeDurations', 'sourceBound', 'authorityEquipment'))
                or setup[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
                or len(final) != 1 or final[0].get('cases') != cases or final[0].get('performed') != len(cases)
                or final[0].get('failed') != 0 or final[0].get('skipped') != 0 or any(r.get('event') == 'fatal' for r in events)):
            issues.append('Missing complete ordered book-controls qualification bank or functional denials remain')
        active = selection.get('options', {}).get('active_edit_observation', False)
        if len(setup) != 1 or setup[0].get('activeEditObserved', False) is not active:
            issues.append('Active-edit observation setup differs from selected option')
        active_rows = raw(text, 'ACTIVE_EDIT_OBSERVATION')
        if [r.get('case') for r in active_rows] != (cases if active else []):
            issues.append('Active-edit raw receipts missing, duplicated, foreign or reordered')
        if selection.get('options', {}).get('precise_timing') is True:
            if len(setup) != 1:
                issues.append('Monotonic timing setup missing')
            else:
                issues.extend(clock_errors(setup[0].get('timingClock')))
        if selection.get('options', {}).get('require_native_requests') is True:
            if len(setup) != 1 or setup[0].get('nativeRequestsObserved') is not True:
                issues.append('Native request diagnostics were not source-bound at setup')
        if selection.get('options', {}).get('require_native_bindings') is True:
            observed = setup[0].get('nativeBindings') if len(setup) == 1 else None
            issues.extend(native_binding_errors(observed, selection.get('options', {}).get('require_extended_native_bindings') is True))
            if raw(text, 'NATIVE_BINDINGS') != [observed]:
                issues.append('Raw native binding-loop evidence differs from setup')
        prepared, baselines, verified = (raw(authority, marker) for marker in ('PREPARED', 'BASELINE', 'VERIFIED'))
        if [r.get('id') for r in rows] != cases or any([r.get('case') for r in values] != cases for values in (prepared, baselines, verified)):
            issues.append('Cases or raw authoritative snapshots missing, duplicated or reordered')
        capacities = raw(authority, 'CAPACITY_LOST')
        if [r.get('case') for r in capacities] != [case for case in cases if case in CAPACITY_CASES]: issues.append('Capacity interventions missing, duplicated or reordered')
        admissions, boundaries, drains, acks = (raw(text, marker) for marker in ('ADMISSION', 'BOUNDARY', 'DRAIN', 'ACK'))
        if any([r.get('case') for r in values] != cases for values in (admissions, boundaries, drains)):
            issues.append('Selected native producer/UI/drain evidence missing, duplicated, foreign or reordered')
        if any(r.get('case') not in cases for r in acks):
            issues.append('Foreign native outcome case')
        stop_rows = raw(text, 'STOP_RETURNED')
        expected_stops = [case for case in cases if base_control(case.split('.', 1)[1]) != 'return-child-cancel'] if selection['mode'] == 'toolkit' else []
        if [r.get('case') for r in stop_rows] != expected_stops:
            issues.append('Native stop return receipts missing, duplicated or reordered')
        timing_rows = raw(text, 'PERFORMANCE')
        if [r.get('case') for r in timing_rows] != cases: issues.append('Timing evidence missing, duplicated or reordered')
        debts, failure_uis = raw(text, 'BLOCKED_RETURN'), raw(text, 'FAILURE_UI')
        expected_failures = [case for case in cases if case in CAPACITY_CASES or selection['kind'] == 'sp' and case in FAVORITE_CASES] if selection['mode'] == 'toolkit' else []
        if [r.get('case') for r in debts] != expected_failures or [r.get('case') for r in failure_uis] != expected_failures:
            issues.append('Exact blocked-return and actual footer evidence missing, duplicated or reordered')
        for i, case in enumerate(cases):
            row = rows[i] if i < len(rows) else {}
            errors = check_case(row, case, selection, prepared[i] if i < len(prepared) else None,
                baselines[i] if i < len(baselines) else None, verified[i] if i < len(verified) else None,
                [r for r in admissions if r.get('case') == case], [r for r in boundaries if r.get('case') == case], [r for r in drains if r.get('case') == case], [r for r in acks if r.get('case') == case], next((r for r in capacities if r.get('case') == case), None),
                [r for r in stop_rows if r.get('case') == case])
            if active:
                receipt = row.get('activeEditObservation')
                if [r for r in active_rows if r.get('case') == case] != [receipt]:
                    errors.append('Raw active-edit receipt differs from its exact case')
                errors.extend(active_edit_errors(receipt, row, case, selection))
            elif row.get('activeEditObservation', False) is not False:
                errors.append('Unrequested active-edit receipt in legacy bank')
            if selection.get('options', {}).get('require_native_requests') is True:
                observed = [r for r in raw(text, 'NATIVE_REQUEST') if r.get('case') == case]
                expected_requests = [sample for record in row.get('records', []) for sample in record.get('requestStates', [])]
                if len(observed) != len(expected_requests):
                    errors.append('Raw native request observation count differs')
                for record in row.get('records', []):
                    if [sample for sample in observed if sample.get('sequence') == record.get('sequence')] != record.get('requestStates', []):
                        errors.append('Raw native request observations differ from their exact owner record')
            for marker, field in (('TRANSFER_STOP_ENTRY', 'nativeStopEntry'), ('TRANSFER_STOP_RETURNED', 'nativeStopReturned')):
                actual = [r for r in raw(text, marker) if r.get('case') == case]
                expected_stops = [r[field] for r in row.get('records', []) if field in r]
                if len(actual) != len(expected_stops) or any(value not in actual for value in expected_stops):
                    errors.append('Raw native transfer stop boundaries differ from exact records')
                if any(r.get('case') not in cases for r in raw(text, marker)):
                    errors.append('Foreign native transfer stop case')
            gap_rows = [r for r in raw(text, 'REPLICA_GAP') if r.get('case') == case]
            converged = [r for r in raw(text, 'REPLICA_CONVERGED') if r.get('case') == case]
            expected_gaps = row.get('replicaGaps', [])
            expected_open = [dict({k:v for k,v in gap.items() if k not in ('resolved', 'resolvedAt')}, emitted=True) for gap in expected_gaps]
            if gap_rows != expected_open or converged != expected_gaps:
                errors.append('Raw exact replica gap/convergence receipts differ from final observed episodes')
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
    return dict(issues=issues, outcomes=outcomes, evidence={'performance': performance_observations(rows),
        'activeEditObservation': [r['activeEditObservation'] for r in rows if isinstance(r.get('activeEditObservation'), dict)], 'limits': [
        'Programmatic real widget hit tests and handlers with an injected drag-threshold state; no physical pointer or rendering claim.',
        'Policy timings cover isolated calls; panelUpdate excludes hover rebuilds. Durations and 20-sample quantiles are diagnostic observations, not design acceptance criteria or complete input/frame cost.',
        'Optional monotonic handler timings observe one actual press/release pair after the diagnostic call bank, without replay; they exclude human pause, rendering and asynchronous settlement.',
        'Performance remains not-assessed until correctness, useful-work cost, complexity, scaling and actual runtime impact are reviewed; a functional pass is not performance approval.',
        'Root singleton cross has no fabricated header; bag/world exercise actual operation/reader/optional-return controls. Four after-edit capacity failures retain an exact visible optional-return obligation, then explicitly Keep the item. Queue-off controls retain native rejected-return/tail-reset behavior.',
        'World normal/capacity books are nonfavorite to isolate eligible return; separate favorite-world SP no-effect/Host native-success probes preserve native protection. No magazine/comic or older-build claim.']})
