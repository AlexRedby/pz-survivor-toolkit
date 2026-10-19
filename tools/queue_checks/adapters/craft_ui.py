"""Native context and batch crafting callbacks with authoritative identity receipts."""
import json
import math
from pathlib import Path
import re

from . import craft


SUCCESS_CASES = ['context', 'vanilla-batch', 'vanilla-auto', 'neat-batch', 'neat-auto', 'cook-batch', 'cook-auto']
CANCEL_CASES = ['context-cancel-active', 'vanilla-cancel-active', 'neat-cancel-active', 'cook-cancel-active']
POOL_CASES = ['vanilla-missing-batch-pool', 'neat-missing-batch-pool', 'cook-missing-batch-pool']
FAILURE_CASES = CANCEL_CASES + POOL_CASES
EVOLVED_CASE = 'cook-evolved-return'
CASES = SUCCESS_CASES + FAILURE_CASES + [EVOLVED_CASE]
COUNTS = {case: 1 if case.startswith('context') else 2 for case in CASES}
OWNERS = {case: ('context' if case.startswith('context') else 'ISWidgetHandCraftControl' if case.startswith('vanilla-')
                 else 'NC_CraftActionPanel' if case.startswith('neat-') else 'PJCK_CraftActionPanel') for case in CASES}
MODS = craft.MODS + ['NeatUI_Framework', 'Neat_Crafting', 'Project_Cook']
RECEIPT_KEYS = {'materialIds', 'consumed', 'outputIds', 'outputs', 'resources', 'toolsReturned', 'bookId', 'tailRead'}
FAILURE_RECEIPT_KEYS = {'materialStates', 'sparePlanks'}
POOL_RECEIPT_KEYS = {'spentMaterials', 'survivingMaterials', 'removedMaterials', 'outputPlankCounts', 'introducedSpare'}
POOL_OBSERVATIONS = {'poolPhaseProof', 'manualMaterialIds', 'manualMaterialIdsAfterRemoval', 'secondAllocated', 'secondStarted'}
FAILURE_OBSERVATIONS = {'interrupted', 'interruptionProgress', 'outcomeTrace', 'playerId', 'tailProgress',
                        'tokenCancelled'}


EVOLVED_RECEIPT_KEYS = {'bags', 'base', 'ingredient', 'spice', 'dishes', 'outputIds', 'outputs', 'bookId', 'tailRead'}
EVOLVED_OBSERVATIONS = {'requested', 'actions', 'actionInputIds', 'progressIds', 'nativeDurations', 'cookingLevel',
                        'sourceMethodsUnchanged', 'callbackClass', 'sourceDeferred', 'sourceVerified', 'tokensGrouped',
                        'tailIndependent', 'tailProgress', 'returnsBeforeRead', 'selectedDishId'}


def _receipt_keys(case):
    if case == EVOLVED_CASE:
        return EVOLVED_RECEIPT_KEYS
    return (RECEIPT_KEYS | (FAILURE_RECEIPT_KEYS if case in FAILURE_CASES else set())
            | (POOL_RECEIPT_KEYS if case in POOL_CASES else set()))


def _metadata(value):
    return (type(value) is dict and set(value) == {'id', 'kind', 'condition', 'uses'}
            and type(value.get('id')) is int and value.get('kind') == 'Base.Plank'
            and all(type(value.get(key)) is int and value[key] >= 0 for key in ('condition', 'uses')))


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _food_meta(value, kind, hunger):
    return (type(value) is dict and set(value) == {'id', 'kind', 'hunger'}
            and type(value.get('id')) is int and value.get('kind') == kind
            and _number(value.get('hunger')) and abs(value['hunger'] - hunger) < .00001)


def _evolved_prepared(prep):
    base = prep.get('base')
    if (set(prep) != {'case', 'bags', 'book', 'base', 'ingredient', 'spice', 'baselineDishIds', 'cookingLevel'}
            or prep.get('case') != EVOLVED_CASE or type(prep.get('cookingLevel')) is not int
            or not 0 <= prep['cookingLevel'] <= 10 or not craft._ids(prep.get('bags'), 2)
            or not craft._ids(prep.get('baselineDishIds')) or type(prep.get('book')) is not int
            or type(base) is not dict or set(base) != {'id', 'kind'}
            or type(base.get('id')) is not int or base.get('kind') != 'Base.Bowl'
            or not _food_meta(prep.get('ingredient'), 'Base.Tomato', -.12)
            or not _food_meta(prep.get('spice'), 'Base.Pepper', -.005)):
        return False
    return craft._ids(prep['bags'] + [prep['book'], base['id'], prep['ingredient']['id'], prep['spice']['id']]
                      + prep['baselineDishIds'])


def _evolved_case(selection, row, prep, receipt):
    issues, enabled = [], selection['mode'] == 'toolkit'
    if not _evolved_prepared(prep):
        return ['Craft UI evolved preparation identity/portion differs'], None
    ids = [prep['ingredient']['id'], prep['spice']['id']]
    level, durations = row.get('cookingLevel'), row.get('nativeDurations')
    if (not craft._matches(row, dict(requested=2, actions=2, actionInputIds=ids, progressIds=[1, 2],
                                    sourceMethodsUnchanged=True, callbackClass='PJCK_EvoPanel', sourceDeferred=True,
                                    sourceVerified=True, tokensGrouped=enabled, tailIndependent=True))
            or type(level) is not int or level != prep['cookingLevel'] or type(durations) is not list or len(durations) != 2
            or any(not _number(duration) or duration != 100 - level * 2.5 for duration in durations)):
        issues.append('Craft UI evolved native UI/action/progress/grouping proof differs')
    keys = EVOLVED_RECEIPT_KEYS
    if (set(receipt) != keys | {'case'} or receipt.get('case') != EVOLVED_CASE
            or not craft._matches(row, {key: receipt.get(key) for key in keys})):
        issues.append('Craft UI evolved authority differs from client')
    expected_shape = craft._matches(row, dict(bags=prep['bags'], bookId=prep['book']))
    base, ingredient, spice, dishes = (row.get(key) for key in ('base', 'ingredient', 'spice', 'dishes'))
    for value, expected, fields in [
        (base, dict(id=prep['base']['id']), {'id', 'totalCount'}),
        (spice, dict(id=prep['spice']['id'], kind='Base.Pepper'), {'id', 'kind', 'totalCount'}),
        (ingredient, dict(id=prep['ingredient']['id'], kind='Base.Tomato'),
         {'id', 'kind', 'hunger', 'sourceCount', 'rootCount', 'totalCount'})]:
        if (type(value) is not dict or set(value) != fields or not craft._matches(value, expected)
                or type(value.get('totalCount')) is not int or value['totalCount'] < 0):
            expected_shape = False
    if (type(ingredient) is not dict or not _number(ingredient.get('hunger'))
            or any(type(ingredient.get(key)) is not int or ingredient[key] not in (0, 1)
                   for key in ('sourceCount', 'rootCount'))
            or ingredient.get('sourceCount', 0) + ingredient.get('rootCount', 0) != ingredient.get('totalCount')):
        expected_shape = False
    outputs, output_ids = row.get('outputs'), row.get('outputIds')
    if (type(outputs) is not int or outputs < 0 or not craft._ids(output_ids, outputs)
            or type(dishes) is not list or len(dishes) != outputs):
        expected_shape = False
    else:
        for dish, identity in zip(dishes, output_ids):
            if (type(dish) is not dict or set(dish) != {'id', 'kind', 'sourceCount', 'rootCount', 'totalCount', 'extras', 'spices'}
                    or not craft._matches(dish, dict(id=identity, kind='Base.Salad', totalCount=1))
                    or any(type(dish.get(key)) is not int or dish[key] not in (0, 1) for key in ('sourceCount', 'rootCount'))
                    or dish.get('sourceCount', 0) + dish.get('rootCount', 0) != 1
                    or any(type(dish.get(key)) is not list or any(type(value) is not str for value in dish[key])
                           for key in ('extras', 'spices'))):
                expected_shape = False
    if not expected_shape:
        issues.append('Craft UI evolved exact effect/endpoint envelope differs')
    owned = prep['bags'] + [prep['book'], prep['base']['id']] + ids + prep['baselineDishIds']
    if not craft._ids(owned + (output_ids if craft._ids(output_ids) else [])):
        issues.append('Craft UI evolved dish is not a new unique replacement identity')
    if (type(row.get('tailRead')) is not bool or type(row.get('tailProgress')) is not bool
            or row.get('tailRead') is not row.get('tailProgress') or type(row.get('returnsBeforeRead')) is not bool
            or row.get('returnsBeforeRead') is True and row.get('tailRead') is not True
            or type(row.get('selectedDishId')) is not int):
        issues.append('Craft UI evolved reader/selection observations differ')
    effect = (expected_shape and outputs == 1 and base['totalCount'] == 0 and spice['totalCount'] == 0
              and ingredient['totalCount'] == 1 and ingredient['sourceCount'] == 1
              and abs(ingredient['hunger'] - (prep['ingredient']['hunger'] + .06 * (1 - .03 * prep['cookingLevel']))) < .00001
              and dishes[0]['sourceCount'] == 1 and dishes[0]['extras'] == ['Base.Tomato']
              and dishes[0]['spices'] == ['Base.Pepper'])
    reason = ('native-evolved-effect-differs' if not effect else 'native-independent-tail-not-preserved'
              if row.get('tailRead') is False else 'native-returns-not-before-tail'
              if row.get('returnsBeforeRead') is False else None)
    if effect and row.get('selectedDishId') != output_ids[0]:
        issues.append('Craft UI evolved selected dish differs from authority replacement')
    if not craft._matches(row, dict(status='failed' if reason else 'passed', reason=reason)):
        issues.append('Craft UI evolved observed status differs')
    if enabled and reason:
        issues.append('Craft UI toolkit evolved continuation/return effect differs: ' + reason)
    return issues, reason


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
        match = re.search(r'\[CRAFT_UI_TEST\] (PREPARED|REMOVED|VERIFIED)(?:\s|$)(.*)', line)
        if match:
            marker, payload = match.groups()
            value = json.loads(payload)
            if type(value) is not dict:
                raise ValueError('Invalid craft UI authoritative envelope')
            result.append((marker, value))
    return result


def _prepared_valid(prep, case):
    if case == EVOLVED_CASE:
        return _evolved_prepared(prep)
    failure = case in FAILURE_CASES
    extra = {'materialMeta', 'sparePlanks', 'playerId'} if failure else set()
    if (set(prep) != {'case', 'materials', 'bags', 'toolMeta', 'book', 'baselineOutputIds'} | extra
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
    spares = []
    if failure:
        materials, spare = prep.get('materialMeta'), prep.get('sparePlanks')
        if (type(materials) is not list or not all(_metadata(meta) for meta in materials)
                or [meta['id'] for meta in materials] != prep['materials'] or type(spare) is not list
                or not all(_metadata(meta) for meta in spare) or type(prep.get('playerId')) is not int):
            return False
        spares = [meta['id'] for meta in spare]
        if spares != sorted(spares):
            return False
    return craft._ids(prep['materials'] + prep['bags'] + tools + [prep.get('book')]
                      + prep['baselineOutputIds'] + spares)


def _case(selection, case, row, prep, receipt, removal=None):
    if case == EVOLVED_CASE:
        return _evolved_case(selection, row, prep, receipt)
    enabled, count = selection['mode'] == 'toolkit', COUNTS[case]
    issues = []
    failure, pooled = case in FAILURE_CASES, case in POOL_CASES
    completed = (1 if pooled else 0) if failure else count
    expected_outputs = row.get('outputs') if pooled and not enabled else completed
    expected = dict(requested=count, actions=count, progressIds=[1] if failure else list(range(1, count + 1)),
                    callbackClass=OWNERS[case], callbacksUnchanged=True, callbackSafe=True,
                    nativeDuration=150, localDeferrals=0, sharedPerformCount=completed if enabled else 0,
                    sharedCompleteCount=completed if enabled and selection['kind'] == 'sp' else 0)
    if pooled and not enabled:
        del expected['progressIds']
    if case.endswith('-auto'):
        expected.update(manualSelect=False, manualInputTypes=['nil'] * count)
    if not craft._matches(row, expected):
        issues.append('Craft UI native callbacks/progress/completion phases differ: ' + case)
    if (type(row.get('ownerIdle')) is not bool or type(row.get('remaining')) is not int or row['remaining'] < 0
            or type(row.get('tailRead')) is not bool or type(row.get('returnsBeforeRead')) is not bool
            or row.get('returnsBeforeRead') is True and row.get('tailRead') is not True):
        issues.append('Craft UI owner/reader/order observations differ: ' + case)
    reason = ('owner-still-busy' if row.get('ownerIdle') is False or type(row.get('remaining')) is int and row['remaining'] > 0
              else 'native-independent-tail-not-preserved' if row.get('tailRead') is False
              else 'native-returns-not-before-tail' if row.get('returnsBeforeRead') is False else None)
    if pooled:
        if row.get('secondAllocated') is True or row.get('secondStarted') is True:
            reason = 'native-second-craft-allocated'
        elif not craft._matches(row, dict(outputs=1, outputPlankCounts=[1])):
            reason = 'native-retained-input-effect-differs'
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
    if case.endswith('-auto') and not craft._same(row.get('automaticToolIds'), [sorted(tools)] * count):
        issues.append('Craft UI automatic selected tool identities differ: ' + case)
    for key in ('pickupIds', 'returnIds'):
        ids = row.get(key)
        if (not craft._ids(ids) or ids != sorted(ids) or not set(ids) <= set(tools)
                or (case.startswith('context') or case.startswith('vanilla-'))
                and (key == 'pickupIds' or not failure or enabled or row.get('returnsBeforeRead') is True)
                and ids != sorted(tools)
                or failure and (case.startswith('neat-') or case.startswith('cook-')) and ids != []):
            issues.append('Craft UI exact observed tool transfers differ: ' + case + '/' + key)
    keys = _receipt_keys(case)
    if (set(receipt) != keys | {'case'} or not craft._matches(receipt, {'case': case})
            or not craft._matches(row, {key: receipt.get(key) for key in keys})):
        issues.append('Craft UI authority differs from client: ' + case)
    if not craft._matches(row, dict(materialIds=prep['materials'], consumed=0 if pooled else completed,
                                   outputs=expected_outputs, bookId=prep['book'])):
        issues.append('Craft UI exact material/reader effect differs: ' + case)
    outputs = row.get('outputIds')
    if (not craft._ids(outputs, expected_outputs) or not craft._ids(prep['materials'] + prep['bags'] + tools
                                                       + [prep['book']] + prep['baselineOutputIds']
                                                       + [meta['id'] for meta in prep.get('sparePlanks', [])] + (outputs or []))):
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
                    or (enabled or row.get('returnsBeforeRead') is True
                        or failure and (case.startswith('neat-') or case.startswith('cook-')))
                    and resource.get('sourceCount') != 1):
                issues.append('Craft UI exact tool conservation/endpoint differs: ' + case)
            else:
                returned += resource['sourceCount']
        if not craft._matches(row, {'toolsReturned': returned}):
            issues.append('Craft UI returned-tool count differs: ' + case)
    if failure:
        issues.extend(_failure(selection, case, row, prep))
    if pooled:
        issues.extend(_pool(selection, case, row, prep, removal or {}))
    return issues, reason


def _failure(selection, case, row, prep):
    issues = []
    progress = row.get('interruptionProgress')
    if (not craft._matches(row, {'interrupted': True, 'playerId': prep['playerId']})
            or type(progress) not in (int, float) or not math.isfinite(progress) or not 0 < progress <= .25
            or type(row.get('tailProgress')) is not bool or row.get('tailRead') is not row.get('tailProgress')
            or (prep['playerId'] < 0 if selection['kind'] == 'mp' else prep['playerId'] != 0)):
        issues.append('Craft UI intervention/reader/actor proof differs: ' + case)
    states = [dict(meta, state='removed' if case in POOL_CASES else 'surviving') for meta in prep['materialMeta']]
    if (not craft._matches(row, dict(materialStates=states, sparePlanks=prep['sparePlanks']))
            or type(row.get('tokenCancelled')) is not bool
            or selection['mode'] == 'toolkit' and row['tokenCancelled'] is not True):
        issues.append('Craft UI exact surviving material evidence differs: ' + case)
    trace = row.get('outcomeTrace')
    if selection['kind'] == 'sp':
        if not craft._same(trace, []):
            issues.append('SP craft UI cannot claim remote native State receipts: ' + case)
    elif type(trace) is not list or len(trace) != 2:
        issues.append('Craft UI native State lifecycle missing/duplicated: ' + case)
    else:
        for entry, state in zip(trace, ('started', 'completed' if case in POOL_CASES else 'canceled')):
            if (type(entry) is not dict or set(entry) != craft.STATE_KEYS
                    or not craft._matches(entry, dict(protocol=1, player=prep['playerId'], kind='ISHandcraftAction', state=state))
                    or type(entry.get('transaction')) is not int or not -128 <= entry['transaction'] <= 127
                    or entry['transaction'] == 0 or type(entry.get('token')) is not str
                    or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', entry['token'])):
                issues.append('Craft UI native State identity/order differs: ' + case)
        if (all(type(entry) is dict for entry in trace)
                and any(not craft._same(trace[0].get(key), trace[1].get(key)) for key in craft.STATE_KEYS - {'state'})):
            issues.append('Craft UI terminal State does not match its started transaction/token: ' + case)
    return issues


def _pool(selection, case, row, prep, removal):
    issues = []
    if (not craft._same(row.get('manualMaterialIds'), [sorted(prep['materials'])] * 2)
            or not craft._same(row.get('manualMaterialIdsAfterRemoval'), [sorted(prep['materials'])] * 2)
            or not craft._same(row.get('poolPhaseProof'), dict(secondAllocatedAtRequest=False,
                              secondAllocatedAtRemoval=False, observedBeforeSecondAllocation=True))):
        issues.append('Craft UI exact shared-pool prestart removal proof differs: ' + case)
    if (set(removal) != {'case', 'removedMaterials', 'introducedSpare'}
            or not craft._matches(removal, dict(case=case, removedMaterials=prep['materialMeta']))
            or not craft._matches(row, dict(spentMaterials=[], survivingMaterials=[], removedMaterials=prep['materialMeta']))):
        issues.append('Craft UI exact removed pool is not independently accounted: ' + case)
    spare = removal.get('introducedSpare')
    if (not _metadata(spare) or not craft._same(row.get('introducedSpare'), spare)
            or not craft._ids(prep['materials'] + prep['bags'] + [meta['id'] for meta in prep['toolMeta']]
                              + [prep['book']] + prep['baselineOutputIds']
                              + [meta['id'] for meta in prep['sparePlanks']]
                              + ([spare['id']] if _metadata(spare) else []) + (row.get('outputIds') or []))):
        issues.append('Craft UI introduced spare is missing, changed or overlaps another identity: ' + case)
    progress, counts = row.get('progressIds'), row.get('outputPlankCounts')
    if (type(row.get('outputs')) is not int or row['outputs'] < 0
            or type(counts) is not list or len(counts) != row['outputs']
            or any(type(count) is not int or count < 0 for count in counts)
            or type(row.get('secondAllocated')) is not bool or type(row.get('secondStarted')) is not bool
            or row.get('secondStarted') is True and row.get('secondAllocated') is not True
            or not craft._ids(progress) or progress not in ([1], [1, 2])
            or progress == [1, 2] and row.get('secondStarted') is not True):
        issues.append('Craft UI actual retained-input/second-action telemetry differs: ' + case)
    if selection['mode'] == 'toolkit' and not craft._matches(row, dict(outputs=1, outputPlankCounts=[1],
                                                                    secondAllocated=False, secondStarted=False)):
        issues.append('Craft UI toolkit did not preserve exactly the first retained-input effect: ' + case)
    return issues


def _outcomes(text):
    return [json.loads(match.group(1)) for match in re.finditer(r'\[CRAFT_UI_TEST\] OUTCOME (.*)', text)]


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
            (marker, case) for case in cases for marker in
            (('PREPARED', 'REMOVED', 'VERIFIED') if case in POOL_CASES else ('PREPARED', 'VERIFIED'))]:
        issues.append('Missing, duplicated or reordered authoritative craft UI receipt')
    identities, output_ids, outcomes, failures = [], [], [], {}
    cleanup_ids = set()
    for case in cases:
        row = next((row for row in results if row.get('id') == case), {})
        prep = next((value for marker, value in raw if marker == 'PREPARED' and value.get('case') == case), {})
        receipt = next((value for marker, value in raw if marker == 'VERIFIED' and value.get('case') == case), {})
        removal = next((value for marker, value in raw if marker == 'REMOVED' and value.get('case') == case), {})
        case_issues, reason = _case(selection, case, row, prep, receipt, removal)
        issues.extend(case_issues)
        if reason and not enabled:
            failures[case] = reason
        if _prepared_valid(prep, case):
            if case == EVOLVED_CASE:
                retained = prep['baselineDishIds']
                owned = prep['bags'] + [prep['book'], prep['base']['id'], prep['ingredient']['id'], prep['spice']['id']]
            else:
                retained = [meta['id'] for meta in prep.get('sparePlanks', [])] + prep['baselineOutputIds']
                owned = prep['materials'] + prep['bags'] + [meta['id'] for meta in prep['toolMeta']] + [prep['book']]
            if cleanup_ids.intersection(retained):
                issues.append('Craft UI previous owned cleanup identity remains in preparation: ' + case)
            identities += owned
            cleanup_ids.update(owned)
        if case in POOL_CASES and _metadata(removal.get('introducedSpare')):
            probe_id = removal['introducedSpare']['id']
            identities.append(probe_id)
            cleanup_ids.add(probe_id)
        if craft._ids(row.get('outputIds')):
            output_ids += row['outputIds']
            cleanup_ids.update(row['outputIds'])
        outcomes.append(dict(actor='client1', case=case, outcome={key: row.get(key) for key in _receipt_keys(case) | (EVOLVED_OBSERVATIONS if case == EVOLVED_CASE else set()) | (FAILURE_OBSERVATIONS if case in FAILURE_CASES else set()) | (POOL_OBSERVATIONS if case in POOL_CASES else set()) | {
            'requested', 'actions', 'progressIds', 'callbackClass', 'callbacksUnchanged', 'callbackSafe',
            'nativeDuration', 'localDeferrals', 'sharedPerformCount', 'sharedCompleteCount', 'ownerIdle',
            'remaining', 'pickupIds', 'returnIds', 'returnsBeforeRead', 'manualSelect', 'manualInputTypes', 'automaticToolIds'}}))
    traces = [dict(case=row.get('id'), receipt=entry) for row in results if row.get('id') in FAILURE_CASES
              for entry in (row.get('outcomeTrace') if type(row.get('outcomeTrace')) is list else [])]
    if not craft._same(_outcomes(text), traces):
        issues.append('Craft UI raw native State receipts differ from case traces')
    tokens = [entry['receipt'].get('token') for entry in traces
              if type(entry['receipt']) is dict and entry['receipt'].get('state') == 'started']
    if any(type(token) is not str for token in tokens) or len(set(tokens)) != len(tokens):
        issues.append('Craft UI native started State token reused between cases')
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
        'Shared-pool loss records retained-cache output effects separately from physical removal; removed items are not reported as normally consumed.',
        'Neat and Project Cook handcraft owners use tools in their source bags; these cases do not claim late tool returns.',
        'Evolved return uses real Salad/Tomato/Pepper actions and source UI with a prepared nearly depleted spice; it does not cover every evolved recipe or retry failure in game.',
        'Fresh one-client SP/Host, native durations and exact authority receipts; no WAN or concurrent-client coverage.']}}
