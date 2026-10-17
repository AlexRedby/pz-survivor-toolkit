"""Native equipment chains; the common runner owns profiles, launch and log audit."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import zipfile

CASES = ['hands-chain', 'waiting-cancel', 'bag-capacity', 'clothing-chain', 'hotbar-chain', 'floor-pickup']
RECEIPTS = {'hands-chain': 3, 'waiting-cancel': 1, 'bag-capacity': 1, 'clothing-chain': 2, 'hotbar-chain': 1, 'floor-pickup': 0}


def definitions():
    return {'equipment': {'status': 'ready', 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
                          'cases': [{'id': case, 'producer': 'inventory', 'capability': 'effect',
                                     'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'],
                                     'modes': ['native', 'toolkit']} for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    if (not isinstance(cases, list) or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or selection.get('languages') not in (['EN'], ['RU'])
            or 'PZSurvivorToolkit' not in selection.get('mods', [])
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Equipment requires an ordered case subset, fresh SP/MP, native/toolkit and one EN/RU client')
    if selection['kind'] == 'mp' and not {'ZombieBuddy', 'PZToolkitJavaPatches'} <= set(selection['mods']):
        raise ValueError('MP equipment requires ZombieBuddy and Toolkit Java Patches')


def sources(project, selection):
    project = Path(project)
    return [*sorted(path for path in (project / 'tests/native_queue/equipment').rglob('*') if path.suffix in ('.lua', '.java')),
            project / 'tests/native_queue/health/shared/QueueHealthEvents.lua',
            project / 'tests/native_queue/startup/client/ZZStartup.lua']


def _transfer_probe(project, output, game, jdk, locations):
    classes = Path(output) / 'equipment-probe/classes'
    classes.mkdir(parents=True)
    classpath = os.pathsep.join(map(str, [Path(game) / 'projectzomboid.jar', Path(game) / 'ZombieBuddy.jar',
                                        Path(locations['PZToolkitJavaPatches']) / '42/media/java/PZToolkitJavaPatches.jar']))
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '17', '-cp', classpath, '-d', str(classes),
                    str(Path(project) / 'tests/native_queue/equipment/java/Main.java')],
                   check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted(classes.rglob('*.class'))
    if not compiled:
        raise ValueError('Equipment transfer probe compilation produced no classes')
    jar = classes.parent / 'EquipmentTransferProbe.jar'
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in compiled:
            archive.write(path, path.relative_to(classes).as_posix())
    return jar


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    probe = _transfer_probe(project, output, game, jdk, locations) if selection['kind'] == 'mp' else None
    if probe:
        runtime.setdefault('fixture', {})['mods'] = ['EquipmentTransferProbe']
    for role in runtime.get('roles', {'client1': {}}):
        lua = Path(output) / role / 'mods/ActionQueueTest/42/media/lua'
        shutil.copy2(Path(project) / 'tests/native_queue/health/shared/QueueHealthEvents.lua', lua / 'shared')
        (lua / 'client').mkdir(exist_ok=True)
        shutil.copy2(Path(project) / 'tests/native_queue/startup/client/ZZStartup.lua', lua / 'client')
        if probe:
            layer = Path(output) / role / 'mods/EquipmentTransferProbe/42'
            (layer / 'media/java').mkdir(parents=True)
            (layer / 'mod.info').write_text('name=Read-only equipment transfer probe\nid=EquipmentTransferProbe\nversionMin=42.21\n'
                                          'require=\\ZombieBuddy\njavaPkgName=net.alexredby.equipmentprobe\n'
                                          'javaJarFile=media/java/EquipmentTransferProbe.jar\n')
            shutil.copy2(probe, layer / 'media/java/EquipmentTransferProbe.jar')
    runtime.setdefault('fixture', {}).update(server_ready='[EQUIPMENT_TEST] SERVER_READY', sandbox={'MinutesPerPage': 2.0})


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
               {'suite': 'equipment', 'kind': selection['kind'], 'mode': selection['mode'], 'actor': 'client1'}.items()):
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
                    'equipmentMatches': True, 'nativeDurations': True, 'postprocessingVerified': True,
                    'policyChecked': selection['mode'] == 'toolkit'}
        if row.get('id') == 'hands-chain':
            required.update(activeProgress=True, activeProtected=selection['mode'] == 'toolkit')
        if row.get('id') == 'waiting-cancel':
            required['cancelled'] = selection['mode'] == 'toolkit'
        if row.get('id') == 'bag-capacity':
            required['capacityBarrier'] = selection['mode'] == 'toolkit'
        if row.get('id') in ('clothing-chain', 'hotbar-chain'):
            required['slotsVerified'] = True
            required['clothing' if row['id'] == 'clothing-chain' else 'hotbar'] = True
        if row.get('id') == 'floor-pickup':
            required.update(floorPickup=True, pickupWorldRemoved=True)
        if selection['kind'] == 'mp':
            required['authoritative'] = True
            count = 0 if row.get('id') == 'waiting-cancel' and selection['mode'] == 'toolkit' else RECEIPTS.get(row.get('id'))
            if type(result.get('receipts')) is not int or result.get('receipts') != count:
                issues.append('Missing native equipment outcome acknowledgements: ' + str(row.get('id')))
            states = result.get('receiptStates')
            allowed = ('completed', 'canceled') if row.get('id') == 'hotbar-chain' else ('completed',)
            if not isinstance(states, list) or len(states) != count or any(state not in allowed for state in states):
                issues.append('Unexpected native equipment terminal states: ' + str(row.get('id')))
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
    if selection['kind'] == 'mp':
        server = (Path(root) / 'server-launch.log').read_text(errors='replace')
        if server.count('[EQUIPMENT_TEST] TRANSFER_PROBE active=true') != 1:
            issues.append('Read-only native transfer probe was not active')
        checkpoints = re.findall(r'\[EQUIPMENT_TEST\] CHECKPOINT case=([a-z-]+)(?:\s|$)', server)
        if checkpoints != selection['cases']:
            issues.append('Authoritative equipment checkpoints missing, duplicated or out of order')
        expected_authority = ['[EQUIPMENT_TEST] AUTHORITY case=' + case + ' inventoryPreserved=true equipmentMatches=true tailCompleted=true' for case in selection['cases']]
        authority = [line.split('[EQUIPMENT_TEST] AUTHORITY ', 1)[1].strip() for line in server.splitlines() if '[EQUIPMENT_TEST] AUTHORITY ' in line]
        if authority != [line.split('AUTHORITY ', 1)[1] for line in expected_authority] or server.count('[EQUIPMENT_TEST] SERVER_READY') != 1 or '[QUEUE_TEST] FAIL ' in server:
            issues.append('Authoritative equipment effects missing, duplicated or out of order')
        captures = re.findall(r'\[EQUIPMENT_TEST\] CAPTURE case=([a-z-]+) kind=(\w+) token=([0-9a-f-]{36})(?:\s|$)', text)
        expected_counts = {case: 0 if case == 'waiting-cancel' and selection['mode'] == 'toolkit' else RECEIPTS[case] for case in selection['cases']}
        if any(sum(case == entry[0] for entry in captures) != count for case, count in expected_counts.items()) or len({entry[2] for entry in captures}) != len(captures) or any(entry[0] not in expected_counts for entry in captures):
            issues.append('Equipment acknowledgement captures missing or duplicated')
    return {'issues': issues, 'outcomes': outcomes,
            'evidence': {'limits': ['Fresh world, one actual client, inventory callbacks invoked programmatically; WAN and physical input unverified.']}}
