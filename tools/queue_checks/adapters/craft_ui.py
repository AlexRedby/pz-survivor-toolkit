"""Native context and batch crafting callbacks with authoritative identity receipts."""
import json
from pathlib import Path
import re

from . import craft


CASES = ['context', 'vanilla-batch', 'neat-batch', 'cook-batch']
COUNTS = dict(zip(CASES, (1, 2, 2, 2)))
OWNERS = dict(zip(CASES, ('context', 'ISWidgetHandCraftControl', 'NC_CraftActionPanel', 'PJCK_CraftActionPanel')))
MODS = craft.MODS + ['NeatUI_Framework', 'Neat_Crafting', 'Project_Cook']
RECEIPT_KEYS = {'materialIds', 'consumed', 'outputIds', 'outputs', 'resources', 'toolsReturned', 'bookId', 'tailRead'}


def definitions():
    return {'craft-ui': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                         'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                                    'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']}
                                   for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('languages') != ['EN'] or type(selection.get('clients', 1)) is not int
            or selection.get('clients', 1) != 1 or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Craft UI requires ordered registered cases, fresh SP/MP, one EN client and all craft UI mods')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'craft-ui').rglob('*.lua')),
            *sorted((root / 'craft/scripts').rglob('*.txt')),
            root / 'health/shared/QueueHealthEvents.lua', *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    craft.stage_common(project, output, game, jdk, selection, locations, runtime)


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[CRAFT_UI_TEST\] COMPLETE(?:\s|$)', text)) == 1


def _authority(text):
    result = []
    for line in text.splitlines():
        match = re.search(r'\[CRAFT_UI_TEST\] (PREPARED|VERIFIED)(?:\s|$)(.*)', line)
        if match:
            marker, payload = match.groups()
            value = json.loads(payload)
            if type(value) is not dict:
                raise ValueError('Invalid craft UI authoritative envelope')
            result.append((marker, value))
    return result


def _prepared_valid(prep, case):
    if (set(prep) != {'case', 'materials', 'bags', 'toolMeta', 'book', 'baselineOutputIds'}
            or not craft._matches(prep, {'case': case}) or not craft._ids(prep.get('materials'), COUNTS[case])
            or not craft._ids(prep.get('bags'), 2) or not craft._ids(prep.get('baselineOutputIds'))
            or type(prep.get('toolMeta')) is not list or len(prep['toolMeta']) != 2):
        return False
    tools = []
    for meta, kind in zip(prep['toolMeta'], ('Base.Hammer', 'Base.Saw')):
        if (type(meta) is not dict or set(meta) != {'id', 'kind', 'condition', 'uses'}
                or not craft._matches(meta, {'kind': kind}) or type(meta.get('id')) is not int
                or any(type(meta.get(key)) is not int or meta[key] < 0 for key in ('condition', 'uses'))):
            return False
        tools.append(meta['id'])
    return craft._ids(prep['materials'] + prep['bags'] + tools + [prep.get('book')] + prep['baselineOutputIds'])


def _case(selection, case, row, prep, receipt):
    enabled, count = selection['mode'] == 'toolkit', COUNTS[case]
    issues = []
    expected = dict(requested=count, actions=count, progressIds=list(range(1, count + 1)),
                    callbackClass=OWNERS[case], callbacksUnchanged=True, callbackSafe=True,
                    nativeDuration=150, localDeferrals=0, sharedPerformCount=count if enabled else 0,
                    sharedCompleteCount=count if enabled and selection['kind'] == 'sp' else 0)
    if not craft._matches(row, expected):
        issues.append('Craft UI native callbacks/progress/completion phases differ: ' + case)
    if (type(row.get('ownerIdle')) is not bool or type(row.get('remaining')) is not int or row['remaining'] < 0
            or type(row.get('tailRead')) is not bool or type(row.get('returnsBeforeRead')) is not bool
            or row.get('returnsBeforeRead') is True and row.get('tailRead') is not True):
        issues.append('Craft UI owner/reader/order observations differ: ' + case)
    reason = ('owner-still-busy' if row.get('ownerIdle') is False or type(row.get('remaining')) is int and row['remaining'] > 0
              else 'native-independent-tail-not-preserved' if row.get('tailRead') is False
              else 'native-returns-not-before-tail' if row.get('returnsBeforeRead') is False else None)
    if enabled:
        if not craft._matches(row, dict(status='passed', reason=None, ownerIdle=True, remaining=0,
                                        tailRead=True, returnsBeforeRead=True, toolsReturned=2)):
            issues.append('Craft UI toolkit continuation/return effect differs: ' + case)
    elif not craft._matches(row, dict(status='failed' if reason else 'passed', reason=reason)):
        issues.append('Craft UI observed native status differs: ' + case)
    if not _prepared_valid(prep, case):
        issues.append('Craft UI preparation identity/metadata differs: ' + case)
        return issues, reason
    tools = [meta['id'] for meta in prep['toolMeta']]
    for key in ('pickupIds', 'returnIds'):
        ids = row.get(key)
        if (not craft._ids(ids) or ids != sorted(ids) or not set(ids) <= set(tools)
                or case in ('context', 'vanilla-batch') and ids != sorted(tools)):
            issues.append('Craft UI exact observed tool transfers differ: ' + case + '/' + key)
    if (set(receipt) != RECEIPT_KEYS | {'case'} or not craft._matches(receipt, {'case': case})
            or not craft._matches(row, {key: receipt.get(key) for key in RECEIPT_KEYS})):
        issues.append('Craft UI authority differs from client: ' + case)
    if not craft._matches(row, dict(materialIds=prep['materials'], consumed=count, outputs=count, bookId=prep['book'])):
        issues.append('Craft UI exact material/reader effect differs: ' + case)
    outputs = row.get('outputIds')
    if (not craft._ids(outputs, count) or not craft._ids(prep['materials'] + prep['bags'] + tools
                                                       + [prep['book']] + prep['baselineOutputIds'] + (outputs or []))):
        issues.append('Craft UI outputs are not new unique native items: ' + case)
    resources, returned = row.get('resources'), 0
    if type(resources) is not list or len(resources) != 2:
        issues.append('Craft UI resource envelope differs: ' + case)
    else:
        for resource, meta in zip(resources, prep['toolMeta']):
            if (type(resource) is not dict or set(resource) != set(meta) | {'sourceCount', 'rootCount'}
                    or not craft._matches(resource, meta)
                    or any(type(resource.get(key)) is not int or resource[key] not in (0, 1)
                           for key in ('sourceCount', 'rootCount'))
                    or resource.get('sourceCount', 0) + resource.get('rootCount', 0) != 1
                    or (enabled or row.get('returnsBeforeRead') is True) and resource.get('sourceCount') != 1):
                issues.append('Craft UI exact tool conservation/endpoint differs: ' + case)
            else:
                returned += resource['sourceCount']
        if not craft._matches(row, {'toolsReturned': returned}):
            issues.append('Craft UI returned-tool count differs: ' + case)
    return issues, reason


def verify(root, selection, catalog):
    from ..report import events
    root, issues = Path(root), []
    logs = {}
    for role in ('client1', 'server') if selection['kind'] == 'mp' else ('client1',):
        try:
            logs[role] = (root / (role + '-launch.log')).read_text(errors='replace')
        except OSError as error:
            logs[role] = ''
            issues.append('Missing craft UI ' + role + ' log: ' + str(error))
    text, authority = logs['client1'], logs['server' if selection['kind'] == 'mp' else 'client1']
    records, raw = events(text), _authority(authority)
    cases, enabled = selection['cases'], selection['mode'] == 'toolkit'
    results = [row for row in records if row['event'] == 'case']
    if not complete(selection, 'client1', text):
        issues.append('Missing or duplicate craft UI completion marker')
    if [row['event'] for row in records] != ['setup'] + ['case'] * len(cases) + ['complete']:
        issues.append('Missing, duplicated or reordered craft UI events')
    if any(not craft._matches(row, dict(suite='craft-ui', kind=selection['kind'], mode=selection['mode'], actor='client1'))
           for row in records):
        issues.append('Craft UI event context differs')
    if [row.get('id') for row in results] != cases:
        issues.append('Craft UI case selection or order differs')
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases),
                                              failed=sum(row.get('status') == 'failed' for row in results), skipped=0))]:
        rows = [row for row in records if row['event'] == event]
        if len(rows) != 1 or not craft._matches(rows[0], expected):
            issues.append('Craft UI ' + event + ' evidence differs')
    if [(marker, value.get('case')) for marker, value in raw] != [
            (marker, case) for case in cases for marker in ('PREPARED', 'VERIFIED')]:
        issues.append('Missing, duplicated or reordered authoritative craft UI receipt')
    identities, output_ids, outcomes, failures = [], [], [], {}
    for case in cases:
        row = next((row for row in results if row.get('id') == case), {})
        prep = next((value for marker, value in raw if marker == 'PREPARED' and value.get('case') == case), {})
        receipt = next((value for marker, value in raw if marker == 'VERIFIED' and value.get('case') == case), {})
        case_issues, reason = _case(selection, case, row, prep, receipt)
        issues.extend(case_issues)
        if reason and not enabled:
            failures[case] = reason
        if _prepared_valid(prep, case):
            identities += prep['materials'] + prep['bags'] + [meta['id'] for meta in prep['toolMeta']] + [prep['book']]
        if craft._ids(row.get('outputIds')):
            output_ids += row['outputIds']
        outcomes.append(dict(actor='client1', case=case, outcome={key: row.get(key) for key in RECEIPT_KEYS | {
            'requested', 'actions', 'progressIds', 'callbackClass', 'callbacksUnchanged', 'callbackSafe',
            'nativeDuration', 'localDeferrals', 'sharedPerformCount', 'sharedCompleteCount', 'ownerIdle',
            'remaining', 'pickupIds', 'returnIds', 'returnsBeforeRead'}}))
    if not craft._ids(identities + output_ids):
        issues.append('Craft UI prepared/output identities overlap between cases')
    if '[QUEUE_TEST] FAIL ' in text or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native craft UI fixture failed')
    for outcome in outcomes:
        reasons = issues + ([failures[outcome['case']]] if outcome['case'] in failures else [])
        outcome.update(status='failed' if reasons else 'passed', reason='; '.join(reasons))
    issues.extend(failures.values())
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Native context and batch callbacks are exercised through fixture-driven UI APIs; physical mouse input is not covered.',
        'Fresh one-client SP/Host, native durations and exact authority receipts; no WAN or concurrent-client coverage.']}}
