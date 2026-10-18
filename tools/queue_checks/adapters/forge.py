"""Actual Primitive Forge crafting through the selected UI and a native Host child."""
from pathlib import Path
import json
import re
import shutil
from ..report import events

CASES = ['handcraft', 'forge', 'forge-shift']


def definitions():
    return {'forge': {'status': 'ready', 'clients': 1,
                      'default_mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'],
                      'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['mp'],
                                     languages=['EN'], modes=['toolkit']) for case in CASES]}}


def validate(selection):
    if (selection.get('cases') != CASES or selection.get('kind') != 'mp'
            or selection.get('mode') != 'toolkit' or selection.get('clients') != 1
            or not selection.get('options', {}).get('mp_host')):
        raise ValueError('Forge requires handcraft,forge,forge-shift in one fresh one-client toolkit Host')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'forge').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'), ('shared', 'QueueHealthEvents.lua')]:
            shutil.copy2(root / ('health' if side == 'shared' else 'startup') / side / name, lua / side / name)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY', 'sandbox': {'Zombies': 6}}


def complete(selection, role, text):
    return role == 'client1' and '[FORGE_TEST] COMPLETE' in text


def verify(root, selection, catalog):
    text = (Path(root) / 'client1-launch.log').read_text(errors='replace')
    records = events(text)
    cases = [row for row in records if row['event'] == 'case']
    issues = []
    server = (Path(root) / 'server-launch.log').read_text(errors='replace')
    receipts = [json.loads(match[1]) for match in re.finditer(r'\[FORGE_TEST\] Verified (\{[^\r\n]+\})', server)]
    if [row.get('id') for row in cases] != CASES or not complete(selection, 'client1', text):
        issues.append('Missing or unordered actual forge cases')
    outcomes = []
    for case in CASES:
        row = next((row for row in cases if row.get('id') == case), {})
        authority = next((receipt for receipt in receipts if receipt.get('case') == case), None)
        passed = (row.get('status') == 'passed' and row.get('authorityVerified') is True
                  and authority is not None and authority == row.get('authority') and authority.get('exactEffects') is True
                  and row.get('queueDrained') is True and row.get('ownerIdle') is True
                  and row.get('nativeDuration') == (1150 if case == 'handcraft' else 1000))
        outcomes.append(dict(actor='client1', case=case, status='passed' if passed else 'failed',
                             reason='' if passed else row.get('reason', 'missing authority or client result'), outcome=row))
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Actual native Host and UI button callbacks; no physical mouse or WAN test.']})
