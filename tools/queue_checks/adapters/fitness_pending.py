"""Evidence for genuine terminal receipts held across a queue-editor transition."""
import json
import math
import re

TARGETS = {'active-cancel-restore': ('ISFitnessAction', 'canceled'),
           'placement-cancel-restore': ('ISDropWorldItemAction', 'completed')}
COMMON = {'case', 'sequence', 'phase', 'at', 'deadline', 'protocol', 'player', 'transaction', 'kind', 'token', 'state',
          'actionRef', 'nativeRef', 'packetRef', 'fingerprint', 'ackBefore', 'ackAfter', 'currentMatches', 'headMatches', 'nativeAbsent'}
PENDING = {'mode', 'editorEnabled', 'sealedStarted', 'tailRetained', 'tailUnread'}


def requested(case, selection):
    return selection.get('options', {}).get('fitness_editor_toggles', {}).get(case) == 'off-pending-outcome'


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def verify_case(case, command, prep, selection):
    rows = command.get('receiptFault')
    error = ['Fitness genuine pending receipt evidence differs: ' + case]
    if not requested(case, selection):
        return error if rows is not None else []
    if case not in TARGETS or type(rows) is not list or len(rows) != 4 or any(type(row) is not dict for row in rows):
        return error
    native = selection['mode'] == 'native'
    packet_fields = ('protocol', 'player', 'transaction', 'kind', 'token', 'state')
    held = rows[0]
    if (any(type(held.get(key)) is not int for key in ('protocol', 'player', 'transaction')) or held['protocol'] != 1
            or held['player'] < 0 or not -128 <= held['transaction'] <= 127 or held['transaction'] == 0
            or (held.get('kind'), held.get('state')) != TARGETS[case]
            or not isinstance(held.get('token'), str)
            or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', held['token'])
            or not number(held.get('at')) or not number(held.get('deadline'))
            or held['deadline'] != held['at'] + selection['options']['fitness_receipt_delay_ms']):
        return error
    if held.get('fingerprint') != '|'.join(str(held[key]) for key in packet_fields):
        return error
    phases = ('retained', 'pending', 'released', 'duplicate')
    immutable = (*packet_fields, 'deadline', 'actionRef', 'nativeRef', 'packetRef', 'fingerprint')
    previous = held['at']
    for index, (row, phase) in enumerate(zip(rows, phases), 1):
        if (set(row) != COMMON | (PENDING if phase == 'pending' else set())
                or row.get('case') != case or type(row.get('sequence')) is not int or row['sequence'] != index
                or row.get('phase') != phase or any(row.get(key) != held.get(key) for key in immutable)
                or any(type(row.get(key)) is not int for key in ('protocol', 'player', 'transaction'))
                or any(not isinstance(row.get(key), str) or not row[key] for key in ('actionRef', 'nativeRef', 'packetRef', 'fingerprint'))
                or not number(row.get('at')) or row['at'] < previous
                or any(type(row.get(key)) is not bool for key in ('currentMatches', 'headMatches', 'nativeAbsent'))
                or row['currentMatches'] != row['headMatches']
                or any(row.get(key) is not False and row.get(key) not in ('started', held['state']) for key in ('ackBefore', 'ackAfter'))):
            return error
        previous = row['at']
    pending, released, duplicate = rows[1:]
    if (not held['at'] <= pending['at'] < held['deadline'] <= released['at'] <= duplicate['at']
            or released['at'] - held['deadline'] > 5000 or duplicate['at'] - released['at'] > 5000
            or any(type(pending.get(key)) is not bool for key in PENDING - {'mode'})
            or pending['mode'] != selection['mode'] or pending['editorEnabled'] is not False
            or pending['nativeAbsent'] is not (case == 'active-cancel-restore') or pending['tailUnread'] is not True
            or pending['sealedStarted'] is not (not native)
            or pending['tailRetained'] is not (not native or case != 'active-cancel-restore')):
        return error
    if not native:
        if (any(row['currentMatches'] is not True for row in (held, pending, released))
                or any(row[key] != 'started' for row in (held, pending) for key in ('ackBefore', 'ackAfter'))
                or released['ackBefore'] != 'started' or released['ackAfter'] != held['state']
                or (duplicate['ackBefore'], duplicate['ackAfter']) not in ((held['state'], held['state']), (False, False))):
            return error
        cancel = command.get('editorCancelBoundary', {})
        if held['nativeRef'] != cancel.get('nativeRef') or held['kind'] != cancel.get('kind') or held['at'] < cancel.get('at', math.inf):
            return error
    elif (released['ackBefore'], released['ackAfter']) not in (('started', held['state']), (False, False)):
        return error
    if native and (any((row['ackBefore'], row['ackAfter']) not in (('started', 'started'), (False, False)) for row in (held, pending))
                   or (duplicate['ackBefore'], duplicate['ackAfter']) not in ((held['state'], held['state']), (False, False))):
        return error
    if case == 'active-cancel-restore' and (command.get('activeAcks') != [held['token']]
            or not native and command.get('terminalAcks') != [dict(token=held['token'], state=held['state'])]):
        return error
    if not native and any(type(row) is not dict or not number(row.get('at')) or row['at'] < released['at']
                          for row in command.get('settledLedgers', [])):
        return error
    tail_at = command.get('receiptFaultTailAt')
    if native and case == 'active-cancel-restore':
        if tail_at is not None and tail_at is not False:
            return error
    elif not number(tail_at) or tail_at < released['at']:
        return error
    return []


def verify_editor(case, command, prep, selection):
    error = ['Fitness editor pending-outcome boundary differs: ' + case]
    cancel, boundary = command.get('editorCancelBoundary'), command.get('editorPendingBoundary')
    transitions, rows = command.get('editorTransitions'), command.get('receiptFault')
    if (type(cancel) is not dict or type(boundary) is not dict or type(transitions) is not list or len(transitions) != 1
            or type(transitions[0]) is not dict or type(rows) is not list or len(rows) != 4 or type(rows[1]) is not dict):
        return error
    transition, held, pending = transitions[0], rows[0], rows[1]
    if (set(boundary) != set(cancel) or boundary.get('boundary') != 'pending-outcome'
            or set(transition) != set(boundary) | {'enabled', 'generationBefore', 'generationAfter'}
            or any(boundary.get(key) != cancel.get(key) for key in ('case', 'nativeRef', 'kind', 'itemId', 'itemType', 'tailId', 'generation'))
            or boundary.get('actionRef') != boundary.get('currentRef')
            or not all(isinstance(boundary.get(key), str) and boundary[key] for key in ('actionRef', 'currentRef', 'token', 'tailRef'))
            or boundary.get('tailId') != prep['items']['tail'] or boundary.get('tailRetained') is not True
            or boundary.get('requestRetained') is not True or boundary.get('drainingAction') is not True or boundary.get('requiredStep') is not False
            or not number(boundary.get('at')) or not held.get('at', math.inf) <= boundary['at'] <= pending.get('at', -math.inf)
            or not number(boundary.get('nativeClock')) or boundary['nativeClock'] < cancel.get('nativeClock', math.inf)
            or any(transition.get(key) != value for key, value in boundary.items() if key not in ('at', 'nativeClock'))
            or transition.get('enabled') is not False or transition.get('nativeClock') != boundary['nativeClock']
            or not number(transition.get('at')) or not boundary['at'] <= transition['at'] <= pending['at']
            or any(type(transition.get(key)) is not int for key in ('generationBefore', 'generationAfter'))
            or transition['generationBefore'] != cancel.get('generation')
            or transition['generationAfter'] not in (transition['generationBefore'], transition['generationBefore'] + 1)
            or command.get('editorEnabled') is not False or 'editorCleanupBoundary' in command):
        return error
    return []


def verify_logs(text, results, selection):
    expected, actual = {}, {}
    for row in results:
        command, case = row.get('command', {}), row.get('id')
        entries = command.get('receiptFault', [])
        if type(entries) is not list:
            return ['Fitness raw receipt fault evidence differs']
        if not requested(case, selection):
            if entries:
                return ['Fitness unexpected raw receipt fault']
            continue
        if len(entries) != 4:
            return ['Fitness raw receipt fault interception missing']
        if selection['mode'] == 'toolkit':
            transitions = command.get('editorTransitions', [])
            if type(transitions) is not list or len(transitions) != 1:
                return ['Fitness raw receipt/editor transition evidence missing']
            expected[case] = [('EDITOR_CANCEL', command.get('editorCancelBoundary')), ('RECEIPT_FAULT', entries[0]),
                              ('EDITOR_PENDING', command.get('editorPendingBoundary')), ('EDITOR_TRANSITION', transitions[0]),
                              *[('RECEIPT_FAULT', entry) for entry in entries[1:]]]
        else:
            expected[case] = [('RECEIPT_FAULT', entry) for entry in entries]
    published, released, active = set(), set(), None
    for line in text.splitlines():
        match = re.search(r'\[FITNESS_TEST\] (RECEIPT_FAULT|EDITOR_CANCEL|EDITOR_PENDING|EDITOR_TRANSITION|SETTLED_LEDGER)\s+([^\n]*)', line)
        if match:
            marker = match[1]
            try:
                value = json.loads(match[2])
            except ValueError:
                return ['Fitness raw receipt/editor evidence is malformed']
            if type(value) is not dict:
                return ['Fitness raw receipt/editor evidence is malformed']
            case = value.get('case')
            if marker == 'RECEIPT_FAULT' and case not in expected:
                return ['Fitness unexpected raw receipt fault']
            if case not in expected:
                continue
            if case in published or active not in (None, case):
                return ['Fitness raw receipt/editor publication order differs']
            active = case
            if marker == 'SETTLED_LEDGER':
                if selection['mode'] == 'toolkit' and case not in released:
                    return ['Fitness required cleanup ledger preceded genuine receipt release']
                continue
            if marker == 'RECEIPT_FAULT' and value.get('phase') == 'released':
                released.add(case)
            actual.setdefault(case, []).append((marker, value))
        elif '[QUEUE_CHECK] ' in line:
            row = json.loads(line.split('[QUEUE_CHECK] ', 1)[1])
            if row.get('event') == 'case':
                case = row.get('id')
                if case in expected and actual.get(case) != expected[case]:
                    return ['Fitness raw receipt/editor chronology differs']
                published.add(case);active = None
    if actual != expected:
        return ['Fitness raw receipt fault evidence differs']
    if selection.get('options', {}).get('fitness_receipt_delay_ms') is not None and not expected:
        outstanding, count = {}, 0
        for match in re.finditer(r'\[FITNESS_TEST\] NATIVE_TRACE\s+([^\n]*)', text):
            row = json.loads(match[1])
            if row.get('boundary') not in ('Receipt.delayed', 'Receipt.released'):
                continue
            action, detail = row.get('action'), row.get('detail')
            if type(action) is not dict or type(detail) is not dict or not number(row.get('wallClock')):
                return ['Fitness delayed receipt identity/clock is malformed']
            key = row.get('case'), action.get('nativeRef'), detail.get('transaction')
            if None in key:
                return ['Fitness delayed receipt identity missing']
            if row['boundary'] == 'Receipt.delayed':
                if key in outstanding:
                    return ['Fitness delayed receipt intercepted twice']
                outstanding[key] = row['wallClock']
            elif key not in outstanding or outstanding.pop(key) >= row['wallClock']:
                return ['Fitness delayed receipt release identity/order differs']
            else:
                count += 1
        if not count or outstanding:
            return ['Fitness configured receipt delay lacks actual interception/release']
    return []
