"""Native SP equipment chains; the common runner owns profiles, launch and log audit."""
from pathlib import Path
import re
import shutil

CASES = ['hands-chain', 'waiting-cancel', 'bag-capacity']


def definitions():
    return {'equipment': {'status': 'ready', 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
                          'cases': [{'id': case, 'producer': 'inventory', 'capability': 'effect',
                                     'kinds': ['sp'], 'languages': ['EN', 'RU'],
                                     'modes': ['native', 'toolkit']} for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (not isinstance(cases, list) or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') != 'sp' or selection.get('mode') not in ('native', 'toolkit')
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or selection.get('languages') not in (['EN'], ['RU'])
            or 'PZSurvivorToolkit' not in selection.get('mods', [])
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Equipment requires an ordered case subset, fresh SP, native/toolkit and one EN/RU client')


def sources(project, selection):
    project = Path(project)
    return [*sorted((project / 'tests/native_queue/equipment').rglob('*.lua')),
            project / 'tests/native_queue/health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    shutil.copy2(Path(project) / 'tests/native_queue/health/shared/QueueHealthEvents.lua',
                 Path(output) / 'client1/mods/ActionQueueTest/42/media/lua/shared')


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[EQUIPMENT_TEST\] COMPLETE(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    from ..report import events
    issues, outcomes = [], []
    text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
    records = events(text)
    expected = ['setup', *['case'] * len(selection['cases']), 'complete']
    if [row['event'] for row in records] != expected:
        issues.append('Missing, duplicated or unordered equipment events')
    for row in records:
        if any(row.get(key) != value for key, value in
               {'suite': 'equipment', 'kind': 'sp', 'mode': selection['mode'], 'actor': 'client1'}.items()):
            issues.append('Equipment event context differs from selection')
    setups = [row for row in records if row['event'] == 'setup']
    if len(setups) != 1 or any(type(setups[0].get(key)) is not type(value) or setups[0].get(key) != value for key, value in {
            'cases': selection['cases'], 'expected': len(selection['cases']), 'nativeDurations': True,
            'queueEnabled': selection['mode'] == 'toolkit'}.items()):
        issues.append('Equipment setup did not prove native timing and queue mode')
    cases = [row for row in records if row['event'] == 'case']
    if [row.get('id') for row in cases] != selection['cases']:
        issues.append('Equipment case IDs differ from selection')
    receipts = [line.split('[EQUIPMENT_TEST] RECEIPT case=', 1)[1].strip()
                for line in text.splitlines() if '[EQUIPMENT_TEST] RECEIPT case=' in line]
    if receipts != selection['cases']:
        issues.append('Missing, duplicate or reordered native equipment receipts')
    for row in cases:
        result = row.get('outcome', {})
        required = {'inventoryPreserved': True, 'frontCompleted': True, 'tailCompleted': True,
                    'equipmentMatches': True, 'nativeDurations': True,
                    'policyChecked': selection['mode'] == 'toolkit'}
        if row.get('id') == 'waiting-cancel':
            required['cancelled'] = selection['mode'] == 'toolkit'
        if row.get('id') == 'bag-capacity':
            required['capacityBarrier'] = selection['mode'] == 'toolkit'
        if row.get('status') != 'passed' or any(result.get(key) is not value for key, value in required.items()):
            issues.append('Equipment effects/guards not verified: ' + str(row.get('id')))
        outcomes.append({'actor': 'client1', 'case': row.get('id'), 'status': row.get('status'),
                         'reason': row.get('reason'), 'outcome': result})
    ends = [row for row in records if row['event'] == 'complete']
    if len(ends) != 1 or any(type(ends[0].get(key)) is not type(value) or ends[0].get(key) != value for key, value in {
            'cases': selection['cases'], 'expected': len(selection['cases']),
            'performed': len(selection['cases']), 'skipped': 0, 'failed': 0}.items()):
        issues.append('Equipment completion counters differ')
    if not complete(selection, 'client1', text) or '[QUEUE_TEST] FAIL ' in text:
        issues.append('Equipment fixture failed or did not finish')
    return {'issues': issues, 'outcomes': outcomes,
            'evidence': {'limits': ['Fresh SP, inventory callbacks invoked programmatically; MP equipment is unverified.']}}
