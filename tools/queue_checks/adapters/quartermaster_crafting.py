"""Bounded native craft-from-storage smoke through vanilla and Neat UI owners."""
import json
from pathlib import Path
import re
import shutil

from . import craft

SUITE = 'quartermaster-crafting'
CASES = ['vanilla', 'neat']
MODS = craft.MODS + ['organizedCategories_core', 'NeatUI_Framework', 'Neat_Crafting']
MARKER = '[QM_CRAFT] '
RECEIPT_KEYS = {'materialIds', 'consumed', 'outputIds', 'outputs', 'resources', 'toolsReturned',
                'bookId', 'tailRead', 'sourceConsumed', 'source'}


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                   'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['toolkit']}
                             for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') != 'toolkit'
            or selection.get('languages') != ['EN'] or type(selection.get('clients', 1)) is not int
            or selection.get('clients', 1) != 1 or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Quartermaster crafting requires ordered vanilla/neat cases, fresh SP/Host, one EN Toolkit client and craft mods')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), root / 'craft-ui/shared/QueueCraftUIFixture.lua',
            *sorted((root / 'craft/scripts').rglob('*.txt')), root / 'health/shared/QueueHealthEvents.lua',
            *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    craft.stage_common(project, output, game, jdk, selection, locations, runtime)
    for role in runtime['roles'].values():
        target = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua/shared'
        shutil.copy2(Path(project) / 'tests/native_queue/craft-ui/shared/QueueCraftUIFixture.lua', target)
    runtime['fixture']['failure_markers'] = [MARKER + 'FAIL ']


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(MARKER) + r'COMPLETE(?:\s|$)', text)) == 1


def _records(text):
    result = []
    for match in re.finditer(re.escape(MARKER) + r'(PREPARED|VERIFIED) (.*)', text):
        value = json.loads(match.group(2))
        if type(value) is not dict:
            raise ValueError('Invalid Quartermaster crafting authority envelope')
        result.append((match.group(1), value))
    return result


def _location(value):
    return (type(value) is dict and set(value) == {'x', 'y', 'z', 'index'}
            and all(type(entry) is int for entry in value.values()) and value['index'] >= 0)


def _case(case, row, prep, receipt):
    expected = dict(id=case, status='passed', recipe='QueueBorrowedTools',
                    callbackClass='ISWidgetHandCraftControl' if case == 'vanilla' else 'NC_CraftActionPanel',
                    ordinarySourceExcluded=True, storageSourceInjected=True, walkProgress=True,
                    materialPickupProgress=True, craftProgress=True, nativeDuration=150, ownerIdle=True)
    if not craft._matches(row, expected):
        raise ValueError('Missing native Quartermaster UI/physical haul/craft progress: ' + case)
    if (set(prep) != {'case', 'materials', 'bags', 'toolMeta', 'book', 'baselineOutputIds', 'source'}
            or prep.get('case') != case or not craft._ids(prep.get('materials'), 1)
            or not craft._ids(prep.get('bags'), 2) or not craft._ids(prep.get('baselineOutputIds'))
            or not _location(prep.get('source')) or type(prep.get('toolMeta')) is not list
            or len(prep['toolMeta']) != 2):
        raise ValueError('Invalid Quartermaster crafting preparation identities: ' + case)
    tools = []
    for meta, kind in zip(prep['toolMeta'], ('Base.Hammer', 'Base.Saw')):
        if (type(meta) is not dict or set(meta) != {'id', 'kind', 'condition', 'uses'}
                or meta.get('kind') != kind or type(meta.get('id')) is not int
                or any(type(meta.get(key)) is not int or meta[key] < 0 for key in ('condition', 'uses'))):
            raise ValueError('Invalid kept-tool preparation metadata: ' + case)
        tools.append(meta['id'])
    identities = prep['materials'] + prep['bags'] + tools + [prep['book']] + prep['baselineOutputIds']
    if not craft._ids(identities):
        raise ValueError('Quartermaster preparation identities overlap: ' + case)
    if (set(receipt) != RECEIPT_KEYS | {'case'} or receipt.get('case') != case
            or not craft._matches(row, {key: receipt.get(key) for key in RECEIPT_KEYS})
            or not craft._matches(receipt, dict(materialIds=prep['materials'], consumed=1, outputs=1,
                                                toolsReturned=2, bookId=prep['book'], sourceConsumed=True,
                                                source=prep['source'], tailRead=False))
            or not craft._ids(receipt.get('outputIds'), 1)
            or not craft._ids(identities + receipt['outputIds'])):
        raise ValueError('Quartermaster exact source consumption/output/authority receipt differs: ' + case)
    transfers = sorted(tools) if case == 'vanilla' else []
    if not craft._matches(row, dict(toolPickupIds=transfers, toolReturnIds=transfers)):
        raise ValueError('Quartermaster observed borrowed-tool transfer identities differ: ' + case)
    resources = receipt.get('resources')
    if type(resources) is not list or len(resources) != 2:
        raise ValueError('Quartermaster kept-tool receipt missing: ' + case)
    for resource, meta in zip(resources, prep['toolMeta']):
        if (type(resource) is not dict or set(resource) != set(meta) | {'sourceCount', 'rootCount'}
                or not craft._matches(resource, dict(meta, sourceCount=1, rootCount=0))):
            raise ValueError('Quartermaster kept-tool identity/condition/source changed: ' + case)
    return prep['materials'] + prep['bags'] + tools + [prep['book']] + receipt['outputIds']


def verify(root, selection, catalog):
    from ..report import events
    root, issues, outcomes = Path(root), [], []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = ((root / 'server-launch.log').read_text(errors='replace')
                     if selection['kind'] == 'mp' else text)
        records, receipts = events(text), _records(authority)
        cases = selection['cases']
        if not complete(selection, 'client1', text) or MARKER + 'FAIL ' in text + authority:
            raise ValueError('Quartermaster crafting completion missing/duplicated or fixture failed')
        if [row['event'] for row in records] != ['setup'] + ['case'] * len(cases) + ['complete']:
            raise ValueError('Quartermaster crafting events missing/duplicated/reordered')
        if any(not craft._matches(row, dict(suite=SUITE, kind=selection['kind'], mode='toolkit', actor='client1'))
               for row in records):
            raise ValueError('Quartermaster crafting event context differs')
        if (not craft._matches(records[0], dict(cases=cases, expected=len(cases), nativeDurations=True))
                or not craft._matches(records[-1], dict(cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))
                or [row.get('id') for row in records[1:-1]] != cases
                or [(kind, value.get('case')) for kind, value in receipts] != [
                    (kind, case) for case in cases for kind in ('PREPARED', 'VERIFIED')]):
            raise ValueError('Quartermaster crafting case or authoritative receipt order differs')
        identities = []
        for index, case in enumerate(cases):
            row = records[index + 1]
            identities += _case(case, row, receipts[index * 2][1], receipts[index * 2 + 1][1])
            outcomes.append(dict(actor='client1', case=case, status='passed', outcome=row))
        if not craft._ids(identities):
            raise ValueError('Quartermaster fixture identities reused between cases')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    if issues:
        outcomes = [dict(actor='client1', case=case, status='failed', reason='; '.join(issues)) for case in selection['cases']]
    return {'issues': issues, 'outcomes': outcomes, 'evidence': {'limits': [
        'Fixture-driven Storage and craft button callbacks; no physical mouse input or layout assertion.',
        'Native QueueBorrowedTools fixture recipe: one distant Plank becomes one WoodenStick2 with kept Hammer/Saw; no recipe catalog or batching coverage.',
        'Vanilla physically retrieves and returns source-bag tools; Neat uses these same tools in their bags.',
        'Fresh one-client SP/Host on the tested platform; no concurrent actors or WAN coverage.']}}
