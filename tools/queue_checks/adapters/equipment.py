"""Native equipment chains; the common runner owns profiles, launch and log audit."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import zipfile

CASES = ['hands-chain', 'waiting-cancel', 'bag-capacity', 'clothing-chain', 'hotbar-chain', 'belt-knife', 'belt-hammer', 'floor-pickup', 'bulk-pickup', 'bulk-waiting-cancel', 'bulk-mixed', 'tidy-hands', 'tidy-floor', 'tidy-empty-hands', 'tidy-group', 'tidy-multigroup', 'tidy-clothing', 'tidy-clothing-remove', 'tidy-clothing-overlap', 'tidy-headwear-hat-remove', 'tidy-headwear-full-hat-remove', 'tidy-hotbar', 'tidy-hotbar-holster-left', 'tidy-hotbar-holster-right']
HOTBAR_CASES = {
    'tidy-hotbar': dict(fullType='Base.Shotgun', slotType='Back', model='Rifle On Back with Bag', twoHands=True),
    'tidy-hotbar-holster-left': dict(fullType='Base.Pistol', slotType='HolsterLeft', model='Holster Left', twoHands=False),
    'tidy-hotbar-holster-right': dict(fullType='Base.Pistol', slotType='HolsterRight', model='Holster Right', twoHands=False),
}
CART_CASE = 'cart-pickup'
CART_TYPES = ['SaucedCarts.ShoppingCart', 'SaucedWheelbarrow.WheelbarrowWood', 'SaucedWheelbarrow.WheelbarrowMetal']
CART_PHASES = ['pickup-first', 'drop', 'pickup-repeat']
RECEIPTS = {'hands-chain': 3, 'waiting-cancel': 1, 'bag-capacity': 1, 'clothing-chain': 2, 'hotbar-chain': 1, 'belt-knife': 1, 'belt-hammer': 1, 'floor-pickup': 0, 'bulk-pickup': 0, 'bulk-waiting-cancel': 0, 'bulk-mixed': 0, 'tidy-hands': 1, 'tidy-floor': 1, 'tidy-empty-hands': 1, 'tidy-group': 1, 'tidy-multigroup': 1, 'tidy-clothing': 0, 'tidy-clothing-remove': 1, 'tidy-clothing-overlap': 2, 'tidy-headwear-hat-remove': 1, 'tidy-headwear-full-hat-remove': 1, 'tidy-hotbar': 1, 'tidy-hotbar-holster-left': 1, 'tidy-hotbar-holster-right': 1}
TIDY_RETURN_CASES = {'hands-chain', 'clothing-chain', 'bulk-mixed', 'tidy-hands', 'tidy-empty-hands', 'tidy-group', 'tidy-multigroup'}
TIDY_RETURN_EXACT_CASES = {'hands-chain', 'tidy-hands', 'tidy-empty-hands', 'tidy-group', 'tidy-multigroup'}


# Each binding names concrete native cases and their required observed outcomes.
SCENARIO_ACTIONS = {
    'equip-hands': {
        'toolkit_only': ['capacity'],
        'scope': 'Bag pickup, two-handed bat, primary hammer and secondary screwdriver; queued behind reading.',
        'checks': {
            'success-queued': {'hands-chain': {'equipmentMatches': True, 'postprocessingVerified': True, 'tailCompleted': True}},
            'move-independent': {'hands-chain': {'independentMoveVerified': True}},
            'move-dependent': {'hands-chain': {'dependentMoveRejected': True}},
            'cancel-waiting': {'waiting-cancel': {'cancelled': True, 'inventoryPreserved': True, 'tailCompleted': True}},
            'cancel-active': {'hands-chain': {'activeProgress': True, 'activeProtected': True}},
            'capacity': {'bag-capacity': {'capacityBarrier': True}},
            'server-authority': {'hands-chain': {'authoritative': True}},
        },
    },
    'pickup-bulk': {
        'scope': 'Selected lightweight/heavy items from a worn bag and an independent transfer; exact item/container identities.',
        'checks': {
            'success-queued': {'bulk-pickup': {'lightMerged': True, 'heavySeparate': True, 'childrenWiped': True, 'exactBulkContainers': True}},
            'cancel-waiting': {'bulk-waiting-cancel': {'bulkCancelled': True, 'unrelatedTailPreserved': True, 'exactBulkContainers': True}},
            'server-authority': {'bulk-pickup': {'authoritative': True}},
        },
    },
    'tidy-hands': {
        'scope': 'P4 borrowed empty pistol rack, occupied/empty hands, and two-item lightweight and four-item light/heavy native return groups; exact containers, repeated native executor attempts and activation.',
        'mods': ['P4TidyUpMeister'],
        'toolkit_only': ['restore-hands', 'return-items', 'move-independent'],
        'checks': {
            'success-queued': {'tidy-hands': {'equipmentMatches': True, 'postprocessingVerified': True, 'tailCompleted': True}},
            'move-independent': {'tidy-hands': {'rackWholeOperationMoveVerified': True, 'rackCancellationProtected': True},
                                 'tidy-empty-hands': {'rackWholeOperationMoveVerified': True, 'rackCancellationProtected': True}},
            'restore-hands': {'tidy-hands': {'restoreVerified': True}, 'tidy-empty-hands': {'restoreVerified': True}},
            'return-items': {'tidy-hands': {'restoreVerified': True, 'postprocessingVerified': True},
                             'tidy-empty-hands': {'restoreVerified': True, 'postprocessingVerified': True},
                             'tidy-group': {'postprocessingVerified': True},
                             'tidy-multigroup': {'postprocessingVerified': True}},
            'server-authority': {'tidy-hands': {'authoritative': True}, 'tidy-empty-hands': {'authoritative': True},
                                 'tidy-group': {'authoritative': True}, 'tidy-multigroup': {'authoritative': True}},
        },
    },
    'tidy-hotbar': {
        'scope': 'Native onRackGun on an initially attached empty Shotgun/Back or Pistol/left/right DoubleHolster with empty hands; P4 generates one fromHotbar Unequip back to its exact native slot. Native attachConnect/model, UI icon, root/worn/hands conservation and independent reading tail.',
        'mods': ['P4TidyUpMeister'],
        'checks': {
            'restore-hotbar': {case: {'equipmentMatches': True, 'postprocessingVerified': True, 'tailCompleted': True} for case in HOTBAR_CASES},
            'server-authority': {case: {'authoritative': True} for case in HOTBAR_CASES},
        },
    },
    'tidy-clothing': {
        'scope': 'Explicit native Unequip-socks + unchanged plain-style CutHair constructors arm real P4 worn restoration; exact socks slot/root identity and unrelated hands/tail. This is not a natural menu socks-removal flow.',
        'mods': ['P4TidyUpMeister'],
        'checks': {
            'restore-clothing': {'tidy-clothing': {'equipmentMatches': True, 'postprocessingVerified': True, 'tailCompleted': True}},
            'server-authority': {'tidy-clothing': {'authoritative': True}},
        },
    },
    'tidy-clothing-remove': {
        'scope': 'Explicit native Wear-socks + unchanged plain-style CutHair constructors capture an initially empty socks slot and arm real P4 worn removal; exact absent slot/root identity and unrelated hands/tail. This bypasses UI explicit-equip intent deliberately.',
        'mods': ['P4TidyUpMeister'],
        'checks': {
            'restore-clothing': {'tidy-clothing-remove': {'equipmentMatches': True, 'postprocessingVerified': True, 'tailCompleted': True}},
            'server-authority': {'tidy-clothing-remove': {'authoritative': True}},
        },
    },
    'tidy-clothing-overlap': {
        'scope': 'Bounded native secondary Equip socks, ordinary Wear and unchanged CutHair constructors produce the same exact held/worn socks; real P4 restores screwdriver before worn removal. Exact initial/final hands, root, source order, generic native receipts and independent tail; no UI explicit-intent coverage implied.',
        'mods': ['P4TidyUpMeister'],
        'checks': {
            'restore-clothing': {'tidy-clothing-overlap': {'equipmentMatches': True, 'postprocessingVerified': True, 'tailCompleted': True}},
            'restore-hands': {'tidy-clothing-overlap': {'equipmentMatches': True, 'postprocessingVerified': True}},
            'server-authority': {'tidy-clothing-overlap': {'authoritative': True}},
        },
    },
    'tidy-headwear-remove': {
        'scope': 'One authority-owned disposable scene preparation removes conflicting starter headwear to root before the baseline. Native Wear and unchanged plain CutHair constructors then temporarily wear vanilla Beany/HAT and BoxingRed/FULL_HAT in that declared scene; real P4 generates removal. Exact item/root/slot/hair/hands and independent tail; conservative capacity excludes native drop. Headwear Wear restoration and Mohawk are outside this gate.',
        'mods': ['P4TidyUpMeister'],
        'checks': {
            'restore-clothing': {case: {'equipmentMatches': True, 'postprocessingVerified': True, 'tailCompleted': True}
                                 for case in ('tidy-headwear-hat-remove', 'tidy-headwear-full-hat-remove')},
            'server-authority': {case: {'authoritative': True} for case in ('tidy-headwear-hat-remove', 'tidy-headwear-full-hat-remove')},
        },
    },
}


def definitions():
    return {'equipment': {'status': 'ready', 'scenario_actions': SCENARIO_ACTIONS, 'clients': 1, 'default_mods': ['PZSurvivorToolkit'],
                          'cases': [{'id': case, 'producer': 'inventory', 'capability': 'effect',
                                     'kinds': ['sp', 'mp'], 'languages': ['EN', 'RU'],
                                     'modes': ['native', 'toolkit']} for case in CASES] +
                                   [{'id': CART_CASE, 'producer': 'inventory', 'capability': 'effect',
                                     'kinds': ['mp'], 'languages': ['EN', 'RU'], 'modes': ['native', 'toolkit']}]}}


def validate(selection):
    cases = selection.get('cases')
    options = selection.get('options', {})
    for key in ('belt_walk', 'belt_favorite'):
        if key in options and type(options[key]) is not bool:
            raise ValueError(key + ' must be Boolean')
        if options.get(key) and (not isinstance(cases, list) or not cases
                                 or any(case not in ('belt-knife', 'belt-hammer') for case in cases)):
            raise ValueError(key + ' requires only belt regression cases')
    if options.get('belt_walk') and not {'ZombieBuddy', 'PZToolkitJavaPatches'} <= set(selection.get('mods', [])):
        raise ValueError('Walking equipment requires ZombieBuddy and Toolkit Java Patches')
    if (not isinstance(cases, list) or not cases or cases != [case for case in [*CASES, CART_CASE] if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or type(selection.get('clients', 1)) is not int or selection.get('clients', 1) != 1
            or selection.get('languages') not in (['EN'], ['RU'])
            or 'PZSurvivorToolkit' not in selection.get('mods', [])
            or selection.get('options', {}).get('world_template')):
        raise ValueError('Equipment requires an ordered case subset, fresh SP/MP, native/toolkit and one EN/RU client')
    if CART_CASE in cases and (cases != [CART_CASE] or selection['kind'] != 'mp'
                               or selection.get('options', {}).get('mp_host') is not True
                               or not {'SaucedCarts', 'saucedwheelbarrow'} <= set(selection['mods'])):
        raise ValueError('cart-pickup requires its own one-client Host MP run and both Sauced cart mods')
    if selection['kind'] == 'mp' and not {'ZombieBuddy', 'PZToolkitJavaPatches'} <= set(selection['mods']):
        raise ValueError('MP equipment requires ZombieBuddy and Toolkit Java Patches')


def sources(project, selection):
    project = Path(project)
    return [*sorted(path for path in (project / 'tests/native_queue/equipment').rglob('*') if path.suffix in ('.lua', '.java')),
            project / 'tests/native_queue/health/shared/QueueHealthEvents.lua',
            project / 'tests/native_queue/support/QueueScenarioChecks.lua',
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
    probe = _transfer_probe(project, output, game, jdk, locations) if selection['kind'] == 'mp' or selection.get('options', {}).get('belt_walk') else None
    if probe:
        runtime.setdefault('fixture', {})['mods'] = ['EquipmentTransferProbe']
    for role in runtime.get('roles', {'client1': {}}):
        lua = Path(output) / role / 'mods/ActionQueueTest/42/media/lua'
        shutil.copy2(Path(project) / 'tests/native_queue/health/shared/QueueHealthEvents.lua', lua / 'shared')
        shutil.copy2(Path(project) / 'tests/native_queue/support/QueueScenarioChecks.lua', lua / 'shared')
        (lua / 'client').mkdir(exist_ok=True)
        shutil.copy2(Path(project) / 'tests/native_queue/startup/client/ZZStartup.lua', lua / 'client')
        if probe:
            layer = Path(output) / role / 'mods/EquipmentTransferProbe/42'
            (layer / 'media/java').mkdir(parents=True)
            (layer / 'mod.info').write_text('name=Isolated native equipment probe\nid=EquipmentTransferProbe\nversionMin=42.21\n'
                                          'require=\\ZombieBuddy\njavaPkgName=net.alexredby.equipmentprobe\n'
                                          'javaJarFile=media/java/EquipmentTransferProbe.jar\n')
            shutil.copy2(probe, layer / 'media/java/EquipmentTransferProbe.jar')
    runtime.setdefault('fixture', {}).update(server_ready='[EQUIPMENT_TEST] SERVER_READY', sandbox={'MinutesPerPage': 2.0})


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[EQUIPMENT_TEST\] COMPLETE(?:\s|$)', text)) == 1


def verify(root, selection, catalog):
    from ..report import events
    if selection['cases'] == [CART_CASE]:
        return _verify_cart(root, selection)
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
        if row.get('id') in ('belt-knife', 'belt-hammer'):
            required.update(policyChecked=False, slotsVerified=True, belt=True, emptyQueueClick=True, favoritePreserved=True)
            if selection.get('options', {}).get('belt_walk'):
                required.update(walkingVerified=True, walkedDuringTransfer=True, walkedDuringAttach=True, walkReleased=True)
                if type(result.get('walkDistance')) not in (int, float) or result.get('walkDistance', 0) <= 0.1:
                    issues.append('Walking belt case lacks native displacement: ' + row['id'])
        if row.get('id') == 'hands-chain':
            required.update(activeProgress=True, activeProtected=selection['mode'] == 'toolkit')
        if row.get('id') == 'waiting-cancel':
            required['cancelled'] = selection['mode'] == 'toolkit'
        if row.get('id') == 'bag-capacity':
            required['capacityBarrier'] = selection['mode'] == 'toolkit'
        if row.get('id') in ('clothing-chain', 'hotbar-chain'):
            required['slotsVerified'] = True
            required['clothing' if row['id'] == 'clothing-chain' else 'hotbar'] = True
        if row.get('id') in ('tidy-hands', 'tidy-empty-hands') and selection['mode'] == 'toolkit':
            required.update(rackWholeOperationMoveVerified=True, rackCancellationProtected=True, independentMoveVerified=True)
        if row.get('id') in ('tidy-hands', 'tidy-floor', 'tidy-empty-hands', 'tidy-group', 'tidy-multigroup'):
            required.update(restoreVerified=True, floorRestoreVerified=row['id'] == 'tidy-floor' and 'P4TidyUpMeister' in selection['mods'])
            count = int(selection['mode'] == 'toolkit' and 'P4TidyUpMeister' in selection['mods'])
            empty = row['id'] == 'tidy-empty-hands'
            actions = count if empty else 4*count
            expected = dict(perform=actions, complete=actions if selection['kind'] == 'sp' else 0,
                            flush=actions, legacy=0, equip=0 if empty else 2*count,
                            activation=0 if empty else 2*count, unequip=count if empty else 0)
            restore = result.get('restoreCompletion')
            if not isinstance(restore, dict) or restore != expected or any(type(v) is not int for v in restore.values()):
                issues.append('P4 equipment restore completion evidence differs: ' + row['id'])
        if row.get('id') == 'floor-pickup':
            required.update(floorPickup=True, pickupWorldRemoved=True)
        if row.get('id', '').startswith('bulk-'):
            required.update(bulkPickup=True, exactBulkContainers=True)
            if row['id'] == 'bulk-waiting-cancel':
                required.update(bulkCancelled=True, unrelatedTailPreserved=True)
            else:
                required.update(lightMerged=True, heavySeparate=True, childrenWiped=True, sharedExecutor=row['id'] == 'bulk-mixed')
            if row['id'] == 'bulk-mixed':
                required['borrowedReturned'] = 'P4TidyUpMeister' in selection['mods']
        if selection['kind'] == 'mp':
            required['authoritative'] = True
            count = 0 if row.get('id') == 'waiting-cancel' and selection['mode'] == 'toolkit' else RECEIPTS.get(row.get('id'))
            if type(result.get('receipts')) is not int or result.get('receipts') != count:
                issues.append('Missing native equipment outcome acknowledgements: ' + str(row.get('id')))
            states = result.get('receiptStates')
            allowed = ('completed', 'canceled') if row.get('id') in ('hotbar-chain', 'belt-knife', 'belt-hammer') else ('completed',)
            if not isinstance(states, list) or len(states) != count or any(state not in allowed for state in states):
                issues.append('Unexpected native equipment terminal states: ' + str(row.get('id')))
        if row.get('status') != 'passed' or any(result.get(key) is not value for key, value in required.items()):
            issues.append('Equipment effects/guards not verified: ' + str(row.get('id')))
        if 'P4TidyUpMeister' in selection['mods']:
            completion = result.get('tidyCompletion')
            valid = (isinstance(completion, dict) and set(completion) == {
                         'perform', 'complete', 'flush', 'legacy', 'explicitConfirmed', 'authoritativeIntent',
                         'cleanupConfirmed', 'authoritativeCleanup'}
                     and all(type(value) is int and value >= 0 for value in completion.values()))
            if valid:
                count = completion['perform']
                valid = (completion['flush'] == (int(selection['mode'] == 'toolkit') if row.get('id') == 'tidy-multigroup' else count) and completion['legacy'] == 0
                         and completion['complete'] == (count if selection['kind'] == 'sp' else 0)
                         and (selection['mode'] != 'native' or count == 0)
                         and completion['authoritativeIntent'] <= completion['explicitConfirmed']
                         and completion['authoritativeCleanup'] <= completion['cleanupConfirmed'])
                if row.get('id') in TIDY_RETURN_EXACT_CASES:
                    cleanup = (4 if row.get('id') == 'tidy-multigroup' else 2 if row.get('id') == 'tidy-group' else count) if selection['mode'] == 'toolkit' else 0
                    valid = (valid and completion['cleanupConfirmed'] == cleanup
                             and completion['authoritativeCleanup'] == (cleanup if selection['kind'] == 'mp' else 0))
                if row.get('id') == 'hands-chain':
                    valid = (valid and completion['explicitConfirmed'] == 3
                             and completion['authoritativeIntent'] == (3 if selection['kind'] == 'mp' else 0))
                elif row.get('id') in ('tidy-hands', 'tidy-empty-hands', 'tidy-group', 'tidy-multigroup'):
                    valid = valid and completion['explicitConfirmed'] == completion['authoritativeIntent'] == 0
            if row.get('id') in ('tidy-group', 'tidy-multigroup') and valid:
                cleanup = (4 if row['id'] == 'tidy-multigroup' else 2) if selection['mode'] == 'toolkit' else 0
                valid = (completion['perform'] == (3 if row['id'] == 'tidy-multigroup' else 1)*int(selection['mode'] == 'toolkit')
                         and completion['cleanupConfirmed'] == cleanup
                         and completion['authoritativeCleanup'] == (cleanup if selection['kind'] == 'mp' else 0))
            if not valid:
                issues.append('Tidy native completion evidence missing or inconsistent: ' + str(row.get('id')))
        if row.get('id') in ('tidy-group', 'tidy-multigroup'):
            issues.extend(_verify_tidy_group(result, selection, multi=row['id'] == 'tidy-multigroup'))
        if row.get('id') in HOTBAR_CASES:
            issues.extend(_verify_tidy_hotbar(result, selection, row['id']))
        if row.get('id') in CLOTHING_CASES:
            issues.extend(_verify_tidy_clothing(result, selection, remove=row['id'] != 'tidy-clothing', overlap=row['id'] == 'tidy-clothing-overlap', case=row['id']))
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
        if 'tidy-floor' in selection['cases'] and 'P4TidyUpMeister' in selection['mods']:
            item = next((row.get('outcome', {}).get('primary') for row in cases if row.get('id') == 'tidy-floor'), None)
            restores = re.findall(r'\[EQUIPMENT_TEST\] FLOOR_RESTORE id=(-?\d+) result=(true|false)(?:\s|$)', server)
            if type(item) is not int or restores != [(str(item), 'true')]:
                issues.append('Exact borrowed floor item did not complete native server placement once')
        group_cases = [case for case in selection['cases'] if case in ('tidy-group', 'tidy-multigroup')]
        clothing_cases = [case for case in selection['cases'] if case in CLOTHING_CASES]
        if any(case in HOTBAR_CASES for case in selection['cases']):
            import json
            markers = [line.split('[EQUIPMENT_TEST] HOTBAR_AUTHORITY ', 1)[1].strip()
                       for line in server.splitlines() if '[EQUIPMENT_TEST] HOTBAR_AUTHORITY ' in line]
            expected = []
            for case in selection['cases']:
                if case not in HOTBAR_CASES:
                    continue
                value = next((row.get('outcome', {}).get('tidyHotbar') for row in cases if row.get('id') == case), {})
                value = value if isinstance(value, dict) else {}
                expected.append({key: value.get(key) for key in HOTBAR_EFFECT_KEYS})
            try:
                authority = [json.loads(marker) for marker in markers]
            except (ValueError, TypeError):
                authority = []
            if (authority != expected or any(not isinstance(value, dict)
                    or any(type(value.get(key)) is not type(wanted) for key, wanted in expected[index].items())
                    for index, value in enumerate(authority))):
                issues.append('Exact P4 hotbar server attachment/root/worn/hands receipt missing or inconsistent')
        if clothing_cases:
            import json
            markers = [line.split('[EQUIPMENT_TEST] CLOTHING_AUTHORITY ', 1)[1].strip()
                       for line in server.splitlines() if '[EQUIPMENT_TEST] CLOTHING_AUTHORITY ' in line]
            expected = []
            for case in clothing_cases:
                value = next((row.get('outcome', {}).get('tidyClothing') for row in cases if row.get('id') == case), {})
                value = value if isinstance(value, dict) else {}
                expected.append({key: value.get(key) for key in clothing_effect_keys(case)})
            try:
                authority = [json.loads(marker) for marker in markers]
            except (ValueError, TypeError):
                authority = []
            if (authority != expected or any(not isinstance(row, dict)
                    or any(type(row.get(key)) is not type(wanted) for key, wanted in expected[index].items())
                    for index, row in enumerate(authority))):
                issues.append('Exact P4 clothing server worn/root receipt missing or inconsistent')
        if group_cases:
            import json
            markers = [line.split('[EQUIPMENT_TEST] GROUP_AUTHORITY ', 1)[1].strip()
                       for line in server.splitlines() if '[EQUIPMENT_TEST] GROUP_AUTHORITY ' in line]
            expected_groups = []
            for case in group_cases:
                group = next((row.get('outcome', {}).get('tidyGroup') for row in cases if row.get('id') == case), {})
                group = group if isinstance(group, dict) else {}
                expected_groups.append(dict(case=case, items=group.get('items'), tailCompleted=True))
            try:
                authority = [json.loads(marker) for marker in markers]
            except (ValueError, TypeError):
                authority = []
            if authority != expected_groups:
                issues.append('Exact P4 group server inventory receipt missing or inconsistent')
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
    scene_issues, scene = _verify_scene(server if selection['kind'] == 'mp' else text, selection)
    issues.extend(scene_issues)
    return {'issues': issues, 'outcomes': outcomes,
            'evidence': {'sceneSetup': scene, 'limits': ['Fresh world, one actual client, inventory callbacks invoked programmatically; WAN and physical input unverified.']}}


def _verify_scene(text, selection):
    import json
    markers = [line.split('[EQUIPMENT_TEST] SCENE_HEADWEAR ', 1)[1].strip()
               for line in text.splitlines() if '[EQUIPMENT_TEST] SCENE_HEADWEAR ' in line]
    needed = any(CLOTHING_SPECS.get(case, {}).get('headwear') for case in selection['cases'])
    if not needed:
        return (['Unexpected headwear scene preparation'] if markers else []), None
    try:
        proof = json.loads(markers[0]) if len(markers) == 1 else None
    except (ValueError, TypeError):
        proof = None
    valid = (isinstance(proof, dict) and set(proof) == {'prepared', 'authority', 'rootRetained', 'normalizedItems'}
             and proof['prepared'] is True and proof['rootRetained'] is True
             and proof['authority'] == ('server' if selection['kind'] == 'mp' else 'sp')
             and isinstance(proof['normalizedItems'], list))
    previous = None
    for item in proof['normalizedItems'] if valid else []:
        if (not isinstance(item, dict) or set(item) != {'id', 'fullType', 'location'}
                or type(item['id']) is not int or item['id'] == -1
                or (previous is not None and item['id'] <= previous)
                or any(type(item[key]) is not str or not item[key] for key in ('fullType', 'location'))):
            valid = False
            break
        previous = item['id']
    return ([] if valid else ['Authority-owned headwear scene preparation/root retention proof missing or inconsistent']), proof


HOTBAR_EFFECT_KEYS = {'case', 'providerItem', 'providerType', 'providerLocation', 'providerWorn', 'id', 'fullType', 'container', 'slotIndex', 'slotType', 'model', 'attached', 'primary', 'secondary',
                      'worn', 'producer', 'producerCompleted', 'ammoUnchanged', 'unrelatedAttachmentsPreserved'}


def _verify_tidy_hotbar(result, selection, case):
    value, checkpoint = result.get('tidyHotbar'), result.get('hotbarCheckpoint')
    tidy = 'P4TidyUpMeister' in selection['mods']
    keys = HOTBAR_EFFECT_KEYS | {'nativeGenerated', 'authoritativeRestore', 'sourceSession', 'sourceCompleted',
                                'attachConnectObserved', 'uiHotbarIdentity', 'sharedCompletion', 'unrelatedTailPreserved'}
    if (not isinstance(value, dict) or set(value) != keys
            or not isinstance(checkpoint, dict) or set(checkpoint) != HOTBAR_EFFECT_KEYS):
        return ['P4 hotbar exact effect/checkpoint evidence missing']
    spec = HOTBAR_CASES[case]
    provider = not spec['twoHands']
    expected = dict(case=case, fullType=spec['fullType'], container='root', slotType=spec['slotType'], model=spec['model'],
                    providerType='Base.HolsterDouble' if provider else False, providerLocation='base:beltextra' if provider else False,
                    providerWorn=provider,
                    attached=tidy, primary=False if tidy else value.get('id'), secondary=value.get('id') if not tidy and spec['twoHands'] else False, worn=False,
                    producer='onRackGun', producerCompleted=True, ammoUnchanged=True, unrelatedAttachmentsPreserved=True,
                    nativeGenerated=int(tidy), authoritativeRestore=tidy and selection['kind'] == 'mp', sourceCompleted=tidy,
                    attachConnectObserved=tidy, uiHotbarIdentity=True, unrelatedTailPreserved=True)
    if (type(value.get('id')) is not int or value['id'] == -1 or type(result.get('hotbarItem')) is not int
            or result['hotbarItem'] != value['id']
            or any(type(value.get(key)) is not type(wanted) or value.get(key) != wanted for key, wanted in expected.items())):
        return ['P4 hotbar exact native slot/model/root/hands effect differs']
    index, provider_id = value.get('slotIndex'), value.get('providerItem')
    if (type(index) is not int or index < 1 or (not provider and index != 1) or (provider and index == 1)
            or (provider and (type(provider_id) is not int or provider_id == -1 or provider_id == value['id']))
            or (not provider and provider_id is not False)):
        return ['P4 hotbar native dynamic slot index or exact worn provider differs']
    session = value.get('sourceSession')
    if (tidy and (type(session) is not int or session <= 0)) or (not tidy and session is not False):
        return ['P4 hotbar source-owned native rack session missing']
    before = {key: value[key] for key in HOTBAR_EFFECT_KEYS}
    before.update(attached=False, primary=value['id'], secondary=value['id'] if spec['twoHands'] else False)
    if checkpoint != before or any(type(checkpoint.get(key)) is not type(wanted) for key, wanted in before.items()):
        return ['P4 hotbar detached/held checkpoint differs from exact restored identity']
    count = int(tidy and selection['mode'] == 'toolkit')
    expected_completion = dict(perform=count, complete=count if selection['kind'] == 'sp' else 0, flush=count, legacy=0)
    completion = value.get('sharedCompletion')
    if (not isinstance(completion, dict) or completion != expected_completion
            or any(type(item) is not int for item in completion.values())):
        return ['P4 hotbar shared completion evidence differs']
    return []


CLOTHING_SPECS = {
    'tidy-clothing': dict(fullType='Base.Socks_Ankle', location='base:socks'),
    'tidy-clothing-remove': dict(fullType='Base.Socks_Ankle', location='base:socks'),
    'tidy-clothing-overlap': dict(fullType='Base.Socks_Ankle', location='base:socks'),
    'tidy-headwear-hat-remove': dict(fullType='Base.Hat_Beany', location='base:hat', headwear=True),
    'tidy-headwear-full-hat-remove': dict(fullType='Base.Hat_BoxingRed', location='base:fullhat', headwear=True),
}
CLOTHING_CASES = tuple(CLOTHING_SPECS)
CLOTHING_OVERLAP_EFFECT_KEYS = {'primary', 'secondary', 'originalSecondary'}


def clothing_effect_keys(case):
    return CLOTHING_EFFECT_KEYS | (CLOTHING_OVERLAP_EFFECT_KEYS if case == 'tidy-clothing-overlap' else set())


CLOTHING_EFFECT_KEYS = {'id', 'fullType', 'bodyLocation', 'container', 'worn', 'producer', 'producerCompleted',
                        'hairUnchanged', 'hairStyle', 'unrelatedHandsPreserved'}


def _verify_tidy_clothing(result, selection, remove=False, overlap=False, case='tidy-clothing'):
    spec = CLOTHING_SPECS[case]
    headwear = spec.get('headwear', False)
    value, checkpoint = result.get('tidyClothing'), result.get('clothingCheckpoint')
    tidy = 'P4TidyUpMeister' in selection['mods']
    effect_keys = CLOTHING_EFFECT_KEYS | (CLOTHING_OVERLAP_EFFECT_KEYS if overlap else set())
    expected_keys = effect_keys | ({'headwearSetup'} if headwear else set()) | ({'overlap'} if overlap else set()) | {'nativeGenerated', 'authoritativeRestore', 'sharedCompletion', 'unrelatedTailPreserved',
                                           'sourceSession', 'sourceCompleted'}
    if (not isinstance(value, dict) or set(value) != expected_keys
            or not isinstance(checkpoint, dict) or set(checkpoint) != effect_keys):
        return ['P4 clothing exact effect/checkpoint evidence missing']
    expected = dict(fullType=spec['fullType'], container='root', worn=(not tidy if remove else tidy), producer='ISCutHair', producerCompleted=True,
                    hairUnchanged=True, unrelatedHandsPreserved=True, nativeGenerated=int(tidy),
                    authoritativeRestore=tidy and selection['kind'] == 'mp', unrelatedTailPreserved=True, sourceCompleted=tidy)
    if (any(type(value.get(key)) is not type(wanted) or value.get(key) != wanted for key, wanted in expected.items())
            or type(value.get('id')) is not int or value['id'] == -1
            or type(result.get('clothingItem')) is not int or result.get('clothingItem') != value['id']
            or value.get('bodyLocation') != spec['location'] or not isinstance(value.get('hairStyle'), str) or not value['hairStyle']
            or any(name in value['hairStyle'] for name in ('Bald', 'Mohawk', 'Spike', 'Greased', 'Buffont'))):
        return ['P4 clothing exact socks/producer/hands evidence differs']
    session = value.get('sourceSession')
    if (tidy and (type(session) is not int or session <= 0)) or (not tidy and session is not False):
        return ['P4 clothing source-owned restore session evidence missing']
    before = {key: value[key] for key in effect_keys}
    before['worn'] = remove
    if overlap:
        before['secondary'] = value['id']
    if checkpoint != before or any(type(checkpoint.get(key)) is not type(value) for key, value in before.items()):
        return ['P4 clothing checkpoint differs from the exact restored socks identity']
    count = int(tidy and selection['mode'] == 'toolkit')
    expected_completion = dict(perform=count, complete=count if selection['kind'] == 'sp' else 0, flush=count, legacy=0)
    completion = value.get('sharedCompletion')
    if (not isinstance(completion, dict) or completion != expected_completion
            or any(type(item) is not int for item in completion.values())):
        return ['P4 clothing shared completion evidence differs']
    if headwear:
        setup = value.get('headwearSetup')
        if (not isinstance(setup, dict) or setup != dict(emptyExclusiveSlots=True, capacityBeforeRemoval=True)
                or any(type(item) is not bool for item in setup.values())):
            return ['P4 headwear empty slots/native capacity setup evidence missing']
    if overlap:
        primary, secondary = value.get('primary'), value.get('originalSecondary')
        if (any(type(item) is not int or item == -1 for item in (primary, secondary))
                or len({primary, secondary, value['id']}) != 3
                or value.get('secondary') != (secondary if tidy else value['id'])):
            return ['P4 overlap exact original/final hands differ']
        proof = value.get('overlap')
        cleanup = [dict(kind='ISEquipWeaponAction', id=secondary), dict(kind='P4RestoreAction', id=secondary),
                   dict(kind='ISUnequipAction', id=value['id'])] if tidy else []
        acknowledgements = [dict(kind='ISEquipWeaponAction', id=value['id']), dict(kind='ISWearClothing', id=value['id']),
                            dict(kind='ISCutHair', id=False)] + cleanup
        acknowledgements = [dict(item, state='completed') for item in acknowledgements] if selection['kind'] == 'mp' else []
        hands = dict(perform=2*count, complete=2*count if selection['kind'] == 'sp' else 0, flush=2*count,
                     legacy=0, equip=count, activation=count, unequip=0)
        expected_proof = dict(intermediate=dict(primary=primary, secondary=value['id'], worn=value['id'], container='root'),
                              cleanup=cleanup, acknowledgements=acknowledgements, sharedHands=hands)
        def strict_equal(actual, wanted):
            if type(actual) is not type(wanted):
                return False
            if isinstance(wanted, dict):
                return actual.keys() == wanted.keys() and all(strict_equal(actual[key], item) for key, item in wanted.items())
            if isinstance(wanted, list):
                return len(actual) == len(wanted) and all(strict_equal(a, b) for a, b in zip(actual, wanted))
            return actual == wanted
        if not strict_equal(proof, expected_proof):
            return ['P4 overlap transition/cleanup order/native receipts/shared hands evidence differs']
    return []


def _verify_tidy_group(result, selection, multi=False):
    group = result.get('tidyGroup')
    tidy = 'P4TidyUpMeister' in selection['mods']
    enabled = selection['mode'] == 'toolkit'
    keys = {'nativeGroups', 'nativeItems', 'groupSizes', 'obligationGroups', 'completedItems', 'items', 'unrelatedTailPreserved',
            'pickupOperations', 'pickupItems', 'ownershipAtBegin', 'ownershipCompleted'}
    if multi:
        keys |= {'executorCount', 'attempts', 'sameNativeExecutor'}
    total = 4 if multi else 2
    if not isinstance(group, dict) or set(group) != keys:
        return ['Bounded P4 native group evidence missing']
    expected = dict(nativeGroups=(3 if multi else 1) if tidy else 0, nativeItems=total if tidy else 0,
                    obligationGroups=int(tidy and enabled), unrelatedTailPreserved=True)
    if any(type(group.get(k)) is not type(v) or group.get(k) != v for k, v in expected.items()):
        return ['Bounded P4 native group counts or unrelated tail differ']
    sizes = group.get('groupSizes')
    expected_sizes = ([1, 1, 2] if multi else [2]) if tidy else []
    if sizes != expected_sizes:
        return ['P4 native group layout differs from observed mode']
    if not isinstance(sizes, list) or any(type(size) is not int for size in sizes):
        return ['P4 native group layout is malformed']
    items, completed = group.get('items'), group.get('completedItems')
    if (not isinstance(items, list) or len(items) != total
            or any(not isinstance(item, dict) or set(item) != {'id', 'fullType', 'container'}
                   or type(item.get('id')) is not int or item['id'] == -1
                   or item.get('fullType') not in (('Base.Nails', 'Base.Hammer') if multi else ('Base.Nails',)) or item.get('container') != ('worn-bag' if tidy else 'root') for item in items)
            or len({item['id'] for item in items}) != total or items != sorted(items, key=lambda item: item['id'])):
        return ['P4 group exact item identities or final containers differ']
    expected_completed = [dict(id=item['id'], fullType=item['fullType'], state='completed') for item in items] if tidy and enabled else []
    if completed != expected_completed or any(type(item.get('id')) is not int for item in completed):
        return ['P4 group per-item completion snapshots missing or inconsistent']
    pickups = group.get('pickupItems')
    ownership_count = total if tidy and enabled else 0
    if (type(group.get('pickupOperations')) is not int or group['pickupOperations'] != int(bool(ownership_count))
            or not isinstance(pickups, list) or len(pickups) != ownership_count):
        return ['P4 confirmed pickup ownership evidence missing or active with queue disabled']
    pickup_keys = {'id', 'fullType', 'owner', 'shared', 'pickupAttempt', 'pickupTransaction', 'pickupAuthority'}
    for pickup in pickups:
        if (not isinstance(pickup, dict) or set(pickup) != pickup_keys
                or type(pickup.get('id')) is not int or type(pickup.get('owner')) is not int or pickup['owner'] != 1
                or type(pickup.get('shared')) is not bool or pickup['shared']
                or type(pickup.get('pickupAttempt')) is not int or pickup['pickupAttempt'] < 1
                or type(pickup.get('pickupTransaction')) is not int
                or pickup.get('pickupAuthority') != ('completed' if selection['kind'] == 'mp' else 'native')):
            return ['P4 original pickup operation or native authority differs']
        transaction = pickup['pickupTransaction']
        if ((selection['kind'] == 'mp' and (transaction == 0 or not -128 <= transaction <= 127))
                or (selection['kind'] == 'sp' and transaction != 0)):
            return ['P4 original pickup inventory transaction differs']
    if ([dict(id=item['id'], fullType=item['fullType'], state='completed') for item in pickups] != expected_completed):
        return ['P4 confirmed pickups omitted, duplicated or changed exact members']
    for field, phase in (('ownershipAtBegin', 'active'), ('ownershipCompleted', 'completed')):
        values = group.get(field)
        expected_ownership = [dict(item, state=phase) for item in pickups]
        if (not isinstance(values, list) or values != expected_ownership
                or any(not isinstance(item, dict) or set(item) != pickup_keys | {'state'}
                       or type(item.get('id')) is not int or type(item.get('owner')) is not int
                       or type(item.get('pickupAttempt')) is not int or type(item.get('pickupTransaction')) is not int
                       or type(item.get('shared')) is not bool for item in values)):
            return ['P4 exact return ownership snapshot missing, partial or foreign: ' + field]
    if multi:
        if (sum(item['fullType'] == 'Base.Nails' for item in items) != 2
                or sum(item['fullType'] == 'Base.Hammer' for item in items) != 2
                or type(group.get('executorCount')) is not int
                or group['executorCount'] != (1 if tidy else 0)
                or group.get('sameNativeExecutor') is not True):
            return ['P4 multi-group executor or exact light/heavy members differ']
        attempts = group.get('attempts')
        if not isinstance(attempts, list) or len(attempts) != (3 if tidy and enabled else 0):
            return ['P4 multi-group attempt ledger missing or incomplete']
        observed, attempt_sizes = [], []
        for ordinal, attempt in enumerate(attempts, 1):
            if (not isinstance(attempt, dict) or set(attempt) != {'ordinal', 'phase', 'state', 'transaction', 'authority', 'items'}
                    or type(attempt.get('ordinal')) is not int or attempt['ordinal'] != ordinal
                    or attempt.get('phase') != 'perform' or attempt.get('state') != 'completed'
                    or attempt.get('authority') != ('completed' if selection['kind'] == 'mp' else 'native')
                    or type(attempt.get('transaction')) is not int):
                return ['P4 multi-group attempt provenance differs']
            transaction = attempt['transaction']
            if ((selection['kind'] == 'mp' and (transaction == 0 or not -128 <= transaction <= 127))
                    or (selection['kind'] == 'sp' and transaction != 0)):
                return ['P4 multi-group native transaction attempts differ']
            members = attempt.get('items')
            if (not isinstance(members, list) or len(members) not in (1, 2)
                    or any(not isinstance(item, dict) or set(item) != {'id', 'fullType', 'state'}
                           or type(item.get('id')) is not int or item.get('state') != 'completed' for item in members)):
                return ['P4 multi-group attempt items differ']
            if len(members) == 2 and any(item['fullType'] != 'Base.Nails' for item in members):
                return ['P4 multi-group merged a heavy native item']
            if len(members) == 1 and members[0]['fullType'] != 'Base.Hammer':
                return ['P4 multi-group lightweight native group was split']
            attempt_sizes.append(len(members));observed.extend(members)
        if attempts and (sorted(attempt_sizes) != [1, 1, 2]
                         or sorted(observed, key=lambda item: item['id']) != expected_completed):
            return ['P4 multi-group ledger omitted or repeated exact IDs']
    return []


def _verify_cart(root, selection):
    """A client success flag cannot replace exact, ordered server ownership receipts."""
    import json
    from ..report import events
    root = Path(root)
    client = (root / 'client1-launch.log').read_text(errors='replace')
    server = (root / 'server-launch.log').read_text(errors='replace')
    issues = []
    records = events(client)
    if [row.get('event') for row in records] != ['setup', 'case', 'complete']:
        issues.append('Missing, duplicated or unordered cart equipment events')
    for row in records:
        if any(row.get(key) != value for key, value in
               dict(suite='equipment', kind='mp', mode=selection['mode'], actor='client1').items()):
            issues.append('Cart equipment event context differs')
    def exact(row, expected):
        return all(type(row.get(key)) is type(value) and row.get(key) == value for key, value in expected.items())
    setup = next((row for row in records if row.get('event') == 'setup'), {})
    if not exact(setup, dict(cases=[CART_CASE], expected=1, nativeDurations=True, queueEnabled=selection['mode'] == 'toolkit')):
        issues.append('Cart setup did not prove native durations and queue mode')
    end = next((row for row in records if row.get('event') == 'complete'), {})
    if not exact(end, dict(cases=[CART_CASE], expected=1, performed=1, skipped=0, failed=0)):
        issues.append('Cart completion counters differ')
    case = next((row for row in records if row.get('event') == 'case'), {})
    outcome = case.get('outcome', {})
    if not exact(case, dict(id=CART_CASE, status='passed')) or not exact(outcome, dict(
            cartPickup=True, inventoryPreserved=True, equipmentMatches=True, cargoPreserved=True,
            nativeDurations=True, postprocessingVerified=True, authoritative=True,
            repeatedPickup=True, nativeDrop=True, cartTypes=CART_TYPES, phases=9)):
        issues.append('Cart pickup/drop effects or authoritative proof missing')
    def markers(text, kind):
        rows = []
        prefix = '[CART_PICKUP] ' + kind + ' '
        for line in text.splitlines():
            if prefix in line:
                try:
                    row = json.loads(line.split(prefix, 1)[1])
                    if not isinstance(row, dict):
                        raise ValueError('marker must be an object')
                    rows.append(row)
                except (ValueError, TypeError):
                    issues.append('Malformed cart ' + kind + ' marker')
        return rows
    clients, servers = markers(client, 'RECEIPT'), markers(server, 'RECEIPT')
    expected = [(index, kind, phase) for index, kind in enumerate(CART_TYPES, 1) for phase in CART_PHASES]
    identities = {}
    for actor, rows in (('client1', clients), ('server', servers)):
        if [(row.get('index'), row.get('type'), row.get('phase')) for row in rows] != expected:
            issues.append('Missing, duplicate or unordered ' + actor + ' cart receipts')
        for row in rows:
            index, phase = row.get('index'), row.get('phase')
            cart_id, cargo_id = row.get('id'), row.get('cargoID')
            if type(index) is not int or type(cart_id) is not int or type(cargo_id) is not int or cart_id == -1 or cargo_id == -1 or cart_id == cargo_id:
                issues.append('Invalid exact cart/cargo identity')
                continue
            identity = (cart_id, cargo_id, row.get('cargoWeight'))
            if index in identities and identities[index] != identity:
                issues.append('Cart/cargo identity or weight changed between client/server phases')
            identities[index] = identity
            ground = phase == 'drop'
            required = dict(actor=actor, cargoPreserved=True, inventoryCount=0 if ground else 1,
                            worldCount=1 if ground else 0, worldAttached=ground, aiming=False,
                            primaryID=-1 if ground else cart_id, secondaryID=-1 if ground else cart_id)
            hold, weight = row.get('holdMs'), row.get('cargoWeight')
            if (not exact(row, required) or type(hold) is not int or hold < 500
                    or type(weight) not in (int, float) or not 0 < weight < 2):
                issues.append('Exact cart/cargo ownership or stable hold missing: ' + actor + '/' + str(phase))
            if actor == 'client1' and (not exact(row, dict(queueEmpty=True, nativeDurations=True))
                    or type(row.get('idleUpdates')) is not int or row['idleUpdates'] < 6
                    or not ground and not exact(row, dict(actionStarted=True, actionProgress=True))):
                issues.append('Cart native action or postprocessing settlement unproven')
            if actor == 'client1' and not ground:
                action_type = row.get('actionType')
                duration = 88 if action_type == 'ToolkitWoodCartPickup' else 50
                if (action_type not in ('ISCartPickupAction', 'ToolkitWoodCartPickup')
                        or action_type == 'ToolkitWoodCartPickup' and row.get('type') != CART_TYPES[1]
                        or type(row.get('actionDuration')) is not int or row['actionDuration'] != duration):
                    issues.append('Cart pickup did not preserve its native/custom action duration')
    if len({value[0] for value in identities.values()}) != 3 or len({value[1] for value in identities.values()}) != 3:
        issues.append('Cart variants reused fixture identities')
    if outcome.get('receipts') != clients:
        issues.append('Cart case outcome differs from client receipts')
    for actor, text in (('client1', client), ('server', server)):
        cleaned = markers(text, 'CLEANED')
        if [(row.get('actor'), row.get('index'), row.get('id')) for row in cleaned] != [
                (actor, index, identities.get(index, (None,))[0]) for index in range(1, 4)]:
            issues.append('Exact cart cleanup acknowledgements missing: ' + actor)
        if '[QUEUE_TEST] FAIL ' in text:
            issues.append('Cart fixture logged a failure: ' + actor)
    if (not complete(selection, 'client1', client)
            or client.count('[EQUIPMENT_TEST] RECEIPT case=cart-pickup') != 1
            or server.count('[EQUIPMENT_TEST] SERVER_READY') != 1
            or server.count('[EQUIPMENT_TEST] TRANSFER_PROBE active=true') != 1):
        issues.append('Cart equipment lifecycle or native transfer probe missing')
    return {'issues': issues, 'outcomes': [{'actor': 'client1', 'case': CART_CASE,
            'status': case.get('status'), 'reason': case.get('reason'), 'outcome': outcome}],
            'evidence': {'limits': ['Fresh one-client Host world; real native cart actions invoked programmatically without aim input.']}}
