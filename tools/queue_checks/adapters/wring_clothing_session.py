"""Validate complete case evidence without promoting an incomplete native session."""
import json
import re

from .. import report
from .wring_clothing import PREFIX, base_case

MARKERS = ('CLIENT_PLACEMENT', 'PREPARED', 'WEAR_BASELINE', 'CAPACITY_LOST',
           'SOURCE_LOST', 'VERIFIED', 'CAPACITY_PROFILE', 'PROFILE_CLEANED',
           'RESTORATION', 'COMPLETE')
AUTHORITY_MARKERS = ('PREPARED', 'WEAR_BASELINE', 'CAPACITY_LOST', 'SOURCE_LOST',
                     'VERIFIED', 'PROFILE_CLEANED')


def _events(text):
    result = []
    offset = 0
    for line in text.splitlines(keepends=True):
        for value in report.events(line):
            if value.get('suite') == 'wring-clothing':
                result.append((offset, value))
        offset += len(line)
    return result


def _markers(text):
    pattern = re.escape(PREFIX) + '(' + '|'.join(MARKERS) + r')(?=[ \t\r\n]|$)(?:[ \t]+([^\n]*))?'
    result = []
    for match in re.finditer(pattern, text):
        value = json.loads(match.group(2) or '')
        if type(value) is not dict:
            raise ValueError('malformed wring raw receipt')
        result.append((match.start(), match.group(1), value))
    return result


def _prefix(actual, expected, label):
    if actual != expected[:len(actual)]:
        raise ValueError('missing, duplicate or out-of-order ' + label)


def _one(markers, name, case):
    rows = [value for _, marker, value in markers if marker == name and value.get('case') == case]
    if len(rows) != 1:
        raise ValueError('missing or duplicate ' + name + ' for ' + case)
    return rows[0]


def _wear(case, selection):
    return (case in ('worn-prepared', 'wear-swap')
            or base_case(case) == 'worn-bag' and selection.get('options', {}).get('profile_capacity', False) is True
            or selection['kind'] == 'mp' and base_case(case) in ('worn', 'worn-bag'))


def _profile(case, selection):
    return case == 'worn-bag' and selection.get('options', {}).get('profile_capacity', False) is True


def _authority_pattern(cases, selection):
    result = []
    for case in cases:
        result.append(('PREPARED', case))
        if _wear(case, selection): result.append(('WEAR_BASELINE', case))
        if case == 'worn-bag-full': result.append(('CAPACITY_LOST', case))
        if case == 'worn-bag-unavailable': result.append(('SOURCE_LOST', case))
        result.append(('VERIFIED', case))
        if _profile(case, selection): result.append(('PROFILE_CLEANED', case))
    return result


def _stream(markers, cases, maximum, label):
    indices = {case: index for index, case in enumerate(cases)}
    positions = []
    for _, name, value in markers:
        if name == 'COMPLETE': continue
        case = value.get('case')
        if type(case) is not str or case not in indices or indices[case] > maximum:
            raise ValueError('unselected or unstarted ' + label + ' receipt')
        positions.append(indices[case])
    if positions != sorted(positions):
        raise ValueError('interleaved or out-of-order ' + label + ' case receipts')


def _one_per_case(markers, name, expected):
    _prefix([value.get('case') for _, marker, value in markers if marker == name], expected, name)


def _case_receipts(case, row, closing, selection, client, authority, check_case):
    # Every client receipt for a completed case must precede its terminal DTO.
    local = [(at, name, value) for at, name, value in client if value.get('case') == case]
    if any(at >= closing for at, _, _ in local):
        raise ValueError('raw case receipt follows its completed DTO')
    placement = _one(client, 'CLIENT_PLACEMENT', case)
    if placement != dict(case=case, proof=row.get('clientPlacement')):
        raise ValueError('actor or placement receipt')
    first = next(at for at, name, value in local if name == 'CLIENT_PLACEMENT')
    if any(at < first for at, _, _ in local):
        raise ValueError('client case receipt precedes placement')
    if any(row.get(key) != expected for key, expected in
           (('actor', 'client1'), ('kind', selection['kind']), ('mode', selection['mode']))):
        raise ValueError('actor or placement receipt')
    prepared = _one(authority, 'PREPARED', case)
    verified = _one(authority, 'VERIFIED', case)
    baseline = _one(authority, 'WEAR_BASELINE', case) if _wear(case, selection) else None
    for name, marker in (('full', 'CAPACITY_LOST'), ('unavailable', 'SOURCE_LOST')):
        if case == 'worn-bag-' + name:
            receipt = _one(authority, marker, case)
            if receipt != _one(client, marker, case) or row['returnControl']['authority'] != receipt:
                raise ValueError('control differs from independent authority receipt')
    if _profile(case, selection):
        measurement = _one(client, 'CAPACITY_PROFILE', case)
        cleanup = _one(authority, 'PROFILE_CLEANED', case)
        if row['capacityProfile']['measurement'] != measurement or row['capacityProfile']['cleanupServer'] != cleanup:
            raise ValueError('capacity profile/cleanup differs from independent raw receipts')
    raw = [value for _, name, value in local if name == 'RESTORATION']
    if raw != row.get('restoration', {}).get('samples', []):
        raise ValueError('restoration event and raw loan receipts differ')
    return check_case(row, selection, prepared, verified, baseline)


def _outcome(case, selection, errors):
    passed = not errors
    return dict(actor='client1', case=case, status='passed' if passed else 'failed', reason='; '.join(errors),
                outcome=dict(effectsVerified=passed, serverAuthorityVerified=passed,
                             tailCompleted=passed and not (case in ('worn-bag-cancel', 'worn-bag-cancel-toggle') and selection['mode'] == 'native'),
                             tailSemanticsVerified=passed,
                             pendingEditsVerified=passed and selection['mode'] == 'toolkit' and base_case(case) in ('root', 'worn-bag', 'worn-prepared', 'wear-swap')))


def verify_streams(text, authority_text, selection, check_case):
    cases = selection['cases']
    if (type(cases) is not list or not cases or any(type(case) is not str for case in cases)
            or len(set(cases)) != len(cases) or type(selection.get('options', {})) is not dict):
        raise ValueError('invalid wring case selection')
    events = _events(text)
    setups = [(at, value) for at, value in events if value['event'] == 'setup']
    ends = [(at, value) for at, value in events if value['event'] == 'complete']
    rows = [(at, value) for at, value in events if value['event'] == 'case']
    if len(setups) != 1 or not events or events[0][1]['event'] != 'setup':
        raise ValueError('exactly one initial wring setup required')
    setup = setups[0][1]
    if (setup.get('cases') != cases or setup.get('queueEnabled') is not (selection['mode'] == 'toolkit')
            or setup.get('nativeDurations') is not True or type(setup.get('adapterInstalled')) is not bool
            or selection['mode'] == 'toolkit' and setup['adapterInstalled'] is not True):
        raise ValueError('setup evidence')
    _prefix([row.get('id') for _, row in rows], cases, 'case evidence')
    passed = 0
    for index, (_, row) in enumerate(rows):
        if row.get('status') == 'passed' and passed == index:
            passed += 1
        elif row.get('status') not in ('failed', 'skipped') or row is not rows[-1][1]:
            raise ValueError('passed case follows missing/failed case evidence')
    errors = [at for at, value in events if value['event'] == 'error']
    if errors and any(at >= errors[0] for at, row in rows if row.get('status') == 'passed'):
        raise ValueError('completed case follows a fixture error')
    client, authority = _markers(text), _markers(authority_text)
    if any(at <= setups[0][0] for at, name, _ in client if name != 'COMPLETE'):
        raise ValueError('client case evidence precedes setup')
    maximum = min(passed, len(cases) - 1)
    _stream(client, cases, maximum, 'client')
    _stream(authority, cases, maximum, 'authority')
    actual = [(name, value.get('case')) for _, name, value in authority if name in AUTHORITY_MARKERS]
    _prefix(actual, _authority_pattern(cases, selection), 'native preparation/baseline/effect/cleanup authority order')
    _one_per_case(client, 'CLIENT_PLACEMENT', cases)
    for index, case in enumerate(cases):
        local = [(at, name) for at, name, value in client if value.get('case') == case]
        if local and (local[0][1] != 'CLIENT_PLACEMENT'
                      or index and (index > len(rows) or rows[index - 1][1].get('status') != 'passed'
                                    or local[0][0] <= rows[index - 1][0])):
            raise ValueError('client case starts before setup/previous terminal boundary')
    profiles = [case for case in cases if _profile(case, selection)]
    if selection.get('options', {}).get('profile_capacity', False) is True and not profiles:
        raise ValueError('capacity profiling requires selected worn-bag')
    _one_per_case(client, 'CAPACITY_PROFILE', profiles)
    for marker, special in (('CAPACITY_LOST', 'worn-bag-full'), ('SOURCE_LOST', 'worn-bag-unavailable')):
        _one_per_case(client, marker, [case for case in cases if case == special])
    for case in cases:
        points = [value.get('point') for _, name, value in client if name == 'RESTORATION' and value.get('case') == case]
        _prefix(points, ['queued', 'body', 'final'], 'raw loan phase order')
    raw_ends = [(at, value) for at, name, value in client if name == 'COMPLETE']
    if len(ends) > 1 or len(raw_ends) > 1:
        raise ValueError('duplicate completion evidence')
    if ends:
        at, end = ends[0]
        if (end.get('cases') != cases or any(type(end.get(key)) is not int for key in ('performed', 'failed', 'skipped'))
                or end.get('performed') != len(cases) or end.get('failed') != 0
                or end.get('skipped') != 0 or len(rows) != len(cases) or passed != len(cases)
                or at <= rows[-1][0] or events[-1][1]['event'] != 'complete'):
            raise ValueError('completion evidence')
    if raw_ends and (raw_ends[0][1] != dict(cases=cases) or passed != len(cases)
                     or raw_ends[0][0] <= (ends[0][0] if ends else rows[-1][0])):
        raise ValueError('raw completion evidence')
    issues = []
    complete = bool(ends and raw_ends)
    if not complete: issues.append('Missing completion marker; wring session remains failed')
    if passed != len(cases): issues.append('Uncompleted wring cases remain unverified')
    if any(value['event'] == 'error' for _, value in events):
        issues.append('Wring fixture error event')
    outcomes, eligible, boundaries = [], [], []
    for index, case in enumerate(cases):
        errors = []
        if index >= passed:
            reason = rows[index][1].get('reason') if index < len(rows) else None
            errors = ['Case has no complete native evidence' + (': ' + str(reason) if reason else '')]
        elif not complete and len(eligible) != index:
            errors = ['Earlier case has no validated cleanup boundary']
        else:
            try:
                errors = _case_receipts(case, rows[index][1], rows[index][0], selection, client, authority, check_case)
            except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
                errors = ['Wring case envelope differs: ' + str(error)]
        outcomes.append(_outcome(case, selection, errors))
        issues.extend(errors)
        if not errors and len(eligible) == index:
            eligible.append(case)
            boundaries.append(dict(case=case, queueIdle=True, authorityVerified=True,
                                   profileCleanup='verified' if _profile(case, selection) else 'not-required'))
    prefix = dict(cases=eligible, uncompletedCases=cases[len(eligible):], boundaries=boundaries,
                  qualification='Case evidence only; common provenance, execution and whole-session acceptance still apply.')
    return dict(issues=issues, outcomes=outcomes, setup=setup, completedPrefix=prefix)


def verify(root, selection, context):
    """Entry for the common fresh-source loader; observations stay in memory."""
    return verify_streams(context['text'], context['authority'], selection, context['check_case'])
