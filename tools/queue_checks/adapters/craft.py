"""Native craft with exact borrowed tools and late return ordering; no UI substitution."""
import json
import math
from pathlib import Path
import re
import shutil

PRESTART_CASES = ['borrowed-tools', 'cancel-pickup', 'missing-input']
ACTIVE_CASES = ['cancel-craft', 'late-input']
CASES = PRESTART_CASES + ACTIVE_CASES
MODS = ['PZSurvivorToolkit', 'ZombieBuddy', 'PZToolkitJavaPatches']


def definitions():
    return {'craft': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                      'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                 'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']}
                                for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (not isinstance(cases, list) or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Craft requires ordered registered cases, fresh SP/MP, one EN client, Toolkit and Java patches')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted(path for path in (root / 'craft').rglob('*') if path.suffix in ('.lua', '.txt')),
            root / 'health/shared/QueueHealthEvents.lua', *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    stage_common(project, output, game, jdk, selection, locations, runtime)


def stage_common(project, output, game, jdk, selection, locations, runtime):
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        media = Path(role['cache']) / 'mods/ActionQueueTest/42/media'
        shutil.copytree(root / 'craft/scripts', media / 'scripts', dirs_exist_ok=True)
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'),
                           ('shared', 'QueueHealthEvents.lua')]:
            target = media / 'lua' / side
            target.mkdir(parents=True, exist_ok=True)
            source = root / ('health' if side == 'shared' else 'startup') / side / name
            shutil.copy2(source, target)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY',
                          'sandbox': {'Zombies': 6, 'MinutesPerPage': 2.0}}


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[CRAFT_QUEUE_TEST\] COMPLETE(?:\s|$)', text)) == 1


AUTHORITY = 'consumed=1 outputs=1 toolsReturned=2 tailRead=true'
RECEIPT_KEYS = ('materialId', 'bookId', 'materialPresent', 'materialCondition', 'materialUses',
                'removed', 'consumed', 'outputs', 'toolsReturned', 'resources', 'tailRead')


def _same(actual, expected):
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(_same(actual[key], value) for key, value in expected.items())
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(_same(left, right) for left, right in zip(actual, expected))
    return actual == expected


def _matches(actual, expected):
    return all(_same(actual.get(key), value) for key, value in expected.items())


def _ids(value, count=None):
    return (type(value) is list and (count is None or len(value) == count)
            and all(type(item) is int for item in value) and len(set(value)) == len(value))


def _authority(text):
    result = []
    pattern = re.compile(r'\[CRAFT_QUEUE_TEST\] (PREPARED|REMOVED|ABORT_AUTHORITY|ACTIVE_AUTHORITY|AUTHORITY)(?:\s|$)(.*)')
    for line in text.splitlines():
        match = pattern.search(line)
        if not match:
            continue
        kind, payload = match.groups()
        value = payload.strip() if kind == 'AUTHORITY' else json.loads(payload)
        if kind != 'AUTHORITY' and type(value) is not dict:
            raise ValueError('Invalid craft authoritative envelope')
        result.append((kind, value))
    return result


def _prepared_valid(prep, case):
    if (not _ids(prep.get('tools'), 2) or not _ids(prep.get('bags'), 2)
            or not _matches(prep, {'case': case}) or type(prep.get('toolMeta')) is not list
            or len(prep['toolMeta']) != 2):
        return False
    ids = prep['tools'] + prep['bags'] + [prep.get('material'), prep.get('book')]
    if case == 'missing-input':
        ids.append(prep.get('blocker'))
    elif prep.get('blocker') is not None:
        return False
    if not _ids(ids) or any(type(prep.get(key)) is not int or prep[key] < 0 for key in
                            ('outputs', 'materialCondition', 'materialUses')):
        return False
    for index, kind in enumerate(('Base.Hammer', 'Base.Saw')):
        meta = prep['toolMeta'][index]
        if (type(meta) is not dict or set(meta) != {'id', 'kind', 'condition', 'uses'}
                or not _matches(meta, {'id': prep['tools'][index], 'kind': kind})
                or any(type(meta.get(key)) is not int or meta[key] < 0 for key in ('condition', 'uses'))):
            return False
    return True


def _abort(case, enabled, row, prep, receipt, removal):
    issues = []
    missing = case == 'missing-input'
    expected = dict(consumed=0, outputs=0, removed=int(missing), materialPresent=not missing,
                    pickupProgress=True, craftProgress=False, interrupted=True, missingObserved=missing,
                    nativeDuration=150, authorityVerified=True, manualInputs=True, localDeferrals=0)
    if enabled:
        expected.update(tailRead=True, tailProgress=True, returnsBeforeRead=True, tokenCancelled=True,
                        toolsReturned=2, status='passed', reason=None)
    if not _matches(row, expected):
        issues.append('Craft abort native effect/progress differs: ' + case)
    for key in ('tailRead', 'tailProgress', 'returnsBeforeRead', 'tokenCancelled'):
        if type(row.get(key)) is not bool:
            issues.append('Craft abort observation must be boolean: ' + case + '/' + key)
    if row.get('tailRead') is not row.get('tailProgress') or (row.get('returnsBeforeRead') is True
                                                           and row.get('tailRead') is not True):
        issues.append('Craft abort reader/order evidence differs: ' + case)
    reason = ('native-independent-tail-not-preserved' if row.get('tailRead') is False else
              'native-returns-not-before-tail' if row.get('returnsBeforeRead') is False else None)
    if not enabled and not _matches(row, {'status': 'failed' if reason else 'passed', 'reason': reason}):
        issues.append('Craft observed native abort status differs: ' + case)
    if not _prepared_valid(prep, case):
        issues.append('Craft abort preparation identity/metadata differs: ' + case)
        return issues, reason if not enabled else None
    if (not _same(row.get('toolIds'), prep['tools']) or not _ids(row.get('pickupIds'), 2)
            or row.get('pickupIds') != sorted(prep['tools']) or not _ids(row.get('returnIds'))
            or row.get('returnIds') != sorted(row.get('returnIds', []))
            or not set(row.get('returnIds', [])) <= set(prep['tools'])
            or (enabled or row.get('returnsBeforeRead') is True) and row.get('returnIds') != sorted(prep['tools'])):
        issues.append('Craft abort exact pickup/return IDs differ: ' + case)
    fields = dict(materialId=prep['material'], bookId=prep['book'], materialCondition=prep['materialCondition'],
                  materialUses=prep['materialUses'], materialPresent=not missing, removed=int(missing), consumed=0, outputs=0)
    if not _matches(row, fields):
        issues.append('Craft abort material/reader identity differs: ' + case)
    resources = row.get('resources')
    returned = 0
    if type(resources) is not list or len(resources) != 2:
        issues.append('Craft abort resource envelope differs: ' + case)
    else:
        for index, resource in enumerate(resources):
            meta = prep['toolMeta'][index]
            if (type(resource) is not dict or set(resource) != set(meta) | {'sourceCount', 'rootCount'}
                    or not _matches(resource, meta)
                    or any(type(resource.get(key)) is not int or resource[key] not in (0, 1)
                           for key in ('sourceCount', 'rootCount'))
                    or resource.get('sourceCount', 0) + resource.get('rootCount', 0) != 1
                    or (enabled or row.get('returnsBeforeRead') is True) and resource.get('sourceCount') != 1):
                issues.append('Craft abort exact tool conservation/endpoint differs: ' + case)
            elif type(resource['sourceCount']) is int:
                returned += resource['sourceCount']
        if not _matches(row, {'toolsReturned': returned}):
            issues.append('Craft abort returned-tool count differs: ' + case)
    if (set(receipt) != set(RECEIPT_KEYS) | {'case'} or not _matches(receipt, {'case': case})
            or not _matches(row, {key: receipt.get(key) for key in RECEIPT_KEYS})):
        issues.append('Craft abort authority differs from client: ' + case)
    if missing and (set(removal) != {'case', 'materialId', 'removed', 'condition', 'uses'} or not _matches(removal,
            dict(case=case, materialId=prep['material'], removed=1,
                 condition=prep['materialCondition'], uses=prep['materialUses']))):
        issues.append('Craft exact removed input differs: ' + case)
    return issues, reason if not enabled else None


ACTIVE_RECEIPT_KEYS = tuple(key for key in RECEIPT_KEYS if key != 'consumed') + (
    'outputIds', 'outputPlankCounts', 'accountedPlanks', 'sparePlanks')
STATE_KEYS = {'protocol', 'player', 'transaction', 'kind', 'token', 'state'}


def _outcome_records(text):
    result = []
    for line in text.splitlines():
        marker = '[CRAFT_QUEUE_TEST] OUTCOME '
        if marker in line:
            value = json.loads(line.split(marker, 1)[1])
            if type(value) is not dict:
                raise ValueError('Invalid craft native State envelope')
            result.append(value)
    return result


def _active(case, selection, row, prep, receipt, removal):
    issues = []
    enabled, late = selection['mode'] == 'toolkit', case == 'late-input'
    expected = dict(outputs=int(late), accountedPlanks=int(late), outputPlankCounts=[1] if late else [],
                    removed=int(late), materialPresent=not late, pickupProgress=True, craftProgress=True,
                    interrupted=True, missingObserved=late, nativeDuration=150, authorityVerified=True,
                    manualInputs=True, localDeferrals=0, sharedPerform=enabled and late,
                    sharedComplete=enabled and late and selection['kind'] == 'sp')
    if enabled:
        expected.update(tailRead=True, tailProgress=True, returnsBeforeRead=True,
                        tokenCancelled=not late, toolsReturned=2, status='passed', reason=None)
    if not _matches(row, expected) or 'consumed' in row:
        issues.append('Craft active effect/accounting/progress differs: ' + case)
    progress = row.get('interruptionProgress')
    if type(progress) not in (int, float) or not math.isfinite(progress) or not 0 < progress <= .25:
        issues.append('Craft intervention missed native active progress window: ' + case)
    for key in ('tailRead', 'tailProgress', 'returnsBeforeRead', 'tokenCancelled'):
        if type(row.get(key)) is not bool:
            issues.append('Craft active observation must be boolean: ' + case + '/' + key)
    if row.get('tailRead') is not row.get('tailProgress') or (row.get('returnsBeforeRead') is True
                                                           and row.get('tailRead') is not True):
        issues.append('Craft active reader/order evidence differs: ' + case)
    reason = ('native-independent-tail-not-preserved' if row.get('tailRead') is False else
              'native-returns-not-before-tail' if row.get('returnsBeforeRead') is False else None)
    if not _matches(row, dict(outputs=int(late), accountedPlanks=int(late))):
        reason = 'native-craft-effect-differs'
    if not enabled and not _matches(row, {'status': 'failed' if reason else 'passed', 'reason': reason}):
        issues.append('Craft observed native active status differs: ' + case)
    if (not _prepared_valid(prep, case) or not _ids(prep.get('outputBaseline'))
            or prep['outputBaseline'] != sorted(prep['outputBaseline']) or len(prep['outputBaseline']) != prep['outputs']
            or type(prep.get('playerId')) is not int or (prep['playerId'] < 0 if selection['kind'] == 'mp' else prep['playerId'] != -1)):
        issues.append('Craft active preparation identity/baseline differs: ' + case)
        return issues, reason if not enabled else None
    spares = prep.get('sparePlanks')
    spare_ids = []
    if type(spares) is list:
        for spare in spares:
            if (type(spare) is not dict or set(spare) != {'id', 'condition', 'uses'}
                    or type(spare.get('id')) is not int
                    or any(type(spare.get(key)) is not int or spare[key] < 0 for key in ('condition', 'uses'))):
                issues.append('Craft active spare Plank metadata differs: ' + case)
                break
            spare_ids.append(spare['id'])
    if (type(spares) is not list or len(spare_ids) != len(spares) or spare_ids != sorted(spare_ids)
            or not _ids(spare_ids + prep['outputBaseline'] + prep['tools'] + prep['bags']
                        + [prep['material'], prep['book']]) or not _same(row.get('sparePlanks'), spares)):
        issues.append('Craft active exact spare Plank conservation differs: ' + case)
    if (not _same(row.get('toolIds'), prep['tools']) or not _ids(row.get('pickupIds'), 2)
            or row.get('pickupIds') != sorted(prep['tools']) or not _ids(row.get('returnIds'))
            or row['returnIds'] != sorted(row['returnIds']) or not set(row['returnIds']) <= set(prep['tools'])
            or (enabled or row.get('returnsBeforeRead') is True) and row['returnIds'] != sorted(prep['tools'])):
        issues.append('Craft active exact pickup/return IDs differ: ' + case)
    if not _matches(row, dict(materialId=prep['material'], bookId=prep['book'], playerId=prep['playerId'],
                             materialCondition=prep['materialCondition'], materialUses=prep['materialUses'])):
        issues.append('Craft active material/reader/actor identity differs: ' + case)
    if (not _ids(row.get('outputIds'), int(late)) or row['outputIds'] != sorted(row['outputIds'])
            or not _ids(prep['outputBaseline'] + prep['tools'] + prep['bags'] + [prep['material'], prep['book']]
                        + spare_ids + row.get('outputIds', []))):
        issues.append('Craft active output IDs are not new unique native outputs: ' + case)
    resources, returned = row.get('resources'), 0
    if type(resources) is not list or len(resources) != 2:
        issues.append('Craft active resource envelope differs: ' + case)
    else:
        for index, resource in enumerate(resources):
            meta = prep['toolMeta'][index]
            if (type(resource) is not dict or set(resource) != set(meta) | {'sourceCount', 'rootCount'}
                    or not _matches(resource, meta)
                    or any(type(resource.get(key)) is not int or resource[key] not in (0, 1)
                           for key in ('sourceCount', 'rootCount'))
                    or resource.get('sourceCount', 0) + resource.get('rootCount', 0) != 1
                    or (enabled or row.get('returnsBeforeRead') is True) and resource.get('sourceCount') != 1):
                issues.append('Craft active exact tool conservation/endpoint differs: ' + case)
            else:
                returned += resource['sourceCount']
        if not _matches(row, {'toolsReturned': returned}):
            issues.append('Craft active returned-tool count differs: ' + case)
    if (set(receipt) != set(ACTIVE_RECEIPT_KEYS) | {'case'} or not _matches(receipt, {'case': case})
            or not _matches(row, {key: receipt.get(key) for key in ACTIVE_RECEIPT_KEYS})):
        issues.append('Craft active authority differs from client: ' + case)
    if late and (set(removal) != {'case', 'materialId', 'removed', 'condition', 'uses'} or not _matches(removal,
            dict(case=case, materialId=prep['material'], removed=1,
                 condition=prep['materialCondition'], uses=prep['materialUses']))):
        issues.append('Craft active exact removed input differs: ' + case)
    trace = row.get('outcomeTrace')
    if selection['kind'] == 'sp':
        if not _same(trace, []):
            issues.append('SP craft cannot claim a remote native State receipt: ' + case)
    elif type(trace) is not list or len(trace) != 2:
        issues.append('Craft active native State lifecycle missing/duplicated: ' + case)
    else:
        for entry, state in zip(trace, ('started', 'completed' if late else 'canceled')):
            if (type(entry) is not dict or set(entry) != STATE_KEYS
                    or not _matches(entry, dict(protocol=1, player=prep['playerId'], kind='ISHandcraftAction', state=state))
                    or type(entry.get('transaction')) is not int or not -128 <= entry['transaction'] <= 127
                    or entry['transaction'] == 0 or type(entry.get('token')) is not str
                    or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', entry['token'])):
                issues.append('Craft active native State identity/order differs: ' + case)
        if (all(type(entry) is dict for entry in trace)
                and any(not _same(trace[0].get(key), trace[1].get(key)) for key in STATE_KEYS - {'state'})):
            issues.append('Craft active terminal State does not match its started transaction/token: ' + case)
    return issues, reason if not enabled else None


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    records, raw = events(text), _authority(authority)
    cases, enabled = selection['cases'], selection['mode'] == 'toolkit'
    issues, outcomes, failures = [], [], {}
    results = [row for row in records if row['event'] == 'case']
    if [row['event'] for row in records] != ['setup'] + ['case'] * len(cases) + ['complete']:
        issues.append('Missing, duplicated or reordered craft events')
    for row in records:
        if not _matches(row, dict(suite='craft', kind=selection['kind'], mode=selection['mode'], actor='client1')):
            issues.append('Craft event context differs')
    if [row.get('id') for row in results] != cases:
        issues.append('Craft case selection or order differs')
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases),
                                              failed=sum(row.get('status') == 'failed' for row in results), skipped=0))]:
        matches = [row for row in records if row['event'] == event]
        if len(matches) != 1 or not _matches(matches[0], expected):
            issues.append('Craft ' + event + ' evidence differs')
    has_abort = any(case != 'borrowed-tools' for case in cases)
    expected_raw = []
    for case in cases:
        if has_abort or any(kind == 'PREPARED' for kind, _ in raw):
            expected_raw.append(('PREPARED', case))
        if case in ('missing-input', 'late-input'):
            expected_raw.append(('REMOVED', case))
        marker = 'AUTHORITY' if case == 'borrowed-tools' else 'ACTIVE_AUTHORITY' if case in ACTIVE_CASES else 'ABORT_AUTHORITY'
        expected_raw.append((marker, case))
    if [(kind, 'borrowed-tools' if kind == 'AUTHORITY' else row.get('case')) for kind, row in raw] != expected_raw:
        issues.append('Missing, duplicated or reordered authoritative craft receipt')
    prepared_ids = []
    for kind, prep in raw:
        if kind == 'PREPARED' and _prepared_valid(prep, prep.get('case')):
            prepared_ids += prep['tools'] + prep['bags'] + [prep['material'], prep['book']]
            if prep.get('blocker') is not None:
                prepared_ids.append(prep['blocker'])
    if not _ids(prepared_ids):
        issues.append('Craft prepared item identities overlap between cases')
    for case in cases:
        row = next((row for row in results if row.get('id') == case), {})
        prep = next((row for kind, row in raw if kind == 'PREPARED' and row.get('case') == case), {})
        if case == 'borrowed-tools':
            expected = dict(status='passed', consumed=1, outputs=1, toolsReturned=2, tailRead=True,
                            returnsBeforeRead=enabled, sharedPerform=enabled, sharedComplete=enabled and selection['kind'] == 'sp',
                            localDeferrals=0, nativeDuration=150, authorityVerified=True)
            if not _matches(row, expected):
                issues.append('Craft case evidence differs')
            if not _ids(row.get('toolIds'), 2) or not _same(row.get('returnOrder'), row.get('toolIds')):
                issues.append('Craft exact tool IDs or native return order differ')
            if (sum(kind == 'AUTHORITY' and value == AUTHORITY for kind, value in raw) != 1
                    or prep and (not _prepared_valid(prep, case) or not _same(row.get('toolIds'), prep['tools']))):
                issues.append('Missing or duplicate authoritative craft receipt')
            outcome = {key: row.get(key) for key in ('consumed', 'outputs', 'toolsReturned', 'tailRead',
                       'returnsBeforeRead', 'localDeferrals', 'nativeDuration', 'authorityVerified')} if row else {}
        elif case in ACTIVE_CASES:
            receipt = next((row for kind, row in raw if kind == 'ACTIVE_AUTHORITY' and row.get('case') == case), {})
            removal = next((row for kind, row in raw if kind == 'REMOVED' and row.get('case') == case), {})
            case_issues, failure = _active(case, selection, row, prep, receipt, removal)
            issues.extend(case_issues)
            if failure:
                failures[case] = failure
            outcome = {key: row.get(key) for key in ACTIVE_RECEIPT_KEYS + ('pickupIds', 'returnIds', 'craftProgress',
                       'tailProgress', 'returnsBeforeRead', 'tokenCancelled', 'interruptionProgress', 'outcomeTrace', 'playerId')}
        else:
            receipt = next((row for kind, row in raw if kind == 'ABORT_AUTHORITY' and row.get('case') == case), {})
            removal = next((row for kind, row in raw if kind == 'REMOVED' and row.get('case') == case), {})
            case_issues, failure = _abort(case, enabled, row, prep, receipt, removal)
            issues.extend(case_issues)
            if failure:
                failures[case] = failure
            outcome = {key: row.get(key) for key in RECEIPT_KEYS + ('pickupIds', 'returnIds', 'craftProgress',
                       'tailProgress', 'returnsBeforeRead', 'tokenCancelled', 'authorityVerified')}
        outcomes.append(dict(actor='client1', case=case, outcome=outcome))
    traces = [row.get('outcomeTrace') for row in results if row.get('id') in ACTIVE_CASES]
    if any(type(trace) is not list for trace in traces):
        issues.append('Craft active native State trace envelope differs')
    else:
        flattened = [entry for trace in traces for entry in trace]
        if not _same(_outcome_records(text), flattened):
            issues.append('Craft active raw State receipts differ from case trace')
        starts = [entry.get('token') for entry in flattened if type(entry) is dict and entry.get('state') == 'started']
        if any(type(token) is not str for token in starts) or len(set(starts)) != len(starts):
            issues.append('Craft active started State token reused between cases')
    if '[QUEUE_TEST] FAIL ' in text or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native craft fixture failed')
    for outcome in outcomes:
        reasons = issues + ([failures[outcome['case']]] if outcome['case'] in failures else [])
        outcome.update(status='failed' if reasons else 'passed', reason='; '.join(reasons))
    issues.extend(failures.values())
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Borrowed-tools late returns are a synthetic base.perform stress case; abort cases use native manual craft/transfer/read methods.',
        'Native abort controls retain observed failures; active output accounting is not proof of physical detached-input consumption.',
        'Active MP State traces must match real incoming started/terminal receipts; shared runtime error auditing is unchanged.',
        'No physical crafting UI, WAN or two-client contention coverage.']}}
