"""Pinned craft: genuine keyboard walking and exact native transfers."""
import json
import math
import os
from pathlib import Path
import re
import shutil
import zipfile
from .. import preparation_process
from . import craft

RECEIPT_KEYS = ('materialId', 'materialPresent', 'materialCondition', 'materialUses', 'consumed', 'outputs',
                'outputIds', 'toolsReturned', 'resources', 'sparePlanks', 'fullOrigin')


def stage(project, output, game, jdk, selection, runtime):
    classes = Path(output) / 'craft-walk-probe/classes'
    classes.mkdir(parents=True)
    classpath = os.pathsep.join(str(Path(game) / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar'))
    preparation_process.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', classpath, '-d', str(classes),
                            str(Path(project) / 'tests/native_queue/craft/java/Main.java')],
                           check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted(classes.rglob('*.class'))
    if not compiled:
        raise ValueError('Craft walk input bridge produced no classes')
    jar = classes.parent / 'CraftWalkInput.jar'
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in compiled:
            archive.write(path, path.relative_to(classes).as_posix())
    runtime.setdefault('fixture', {}).setdefault('mods', []).append('CraftWalkInput')
    for role in runtime['roles'].values():
        layer = Path(role['cache']) / 'mods/CraftWalkInput/42'
        (layer / 'media/java').mkdir(parents=True)
        (layer / 'mod.info').write_text('name=Disposable craft native walk input\nid=CraftWalkInput\nversionMin=42.21\n'
                                      'require=\\ZombieBuddy\njavaPkgName=toolkit.craftwalk\n'
                                      'javaJarFile=media/java/CraftWalkInput.jar\n')
        shutil.copy2(jar, layer / 'media/java/CraftWalkInput.jar')


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def verify(root, selection):
    from ..report import events
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    records = events(text)
    raw = []
    for match in re.finditer(r'\[CRAFT_QUEUE_TEST\] (PREPARED|WALK_AUTHORITY) (.*)', authority):
        value = json.loads(match[2])
        if type(value) is not dict:
            raise ValueError('Invalid walking craft authority envelope')
        raw.append((match[1], value))
    cases = selection['cases']; issues = []; outcomes = []
    enabled = selection['mode'] == 'toolkit'
    if [row['event'] for row in records] != ['setup'] + ['case'] * len(cases) + ['complete']:
        issues.append('Missing, duplicated or reordered walking craft events')
    for row in records:
        if not craft._matches(row, dict(suite='craft', kind=selection['kind'], mode=selection['mode'], actor='client1')):
            issues.append('Walking craft context differs')
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))]:
        values = [row for row in records if row['event'] == event]
        if len(values) != 1 or not craft._matches(values[0], expected):
            issues.append('Walking craft ' + event + ' differs')
    rows = [row for row in records if row['event'] == 'case']
    if [row.get('id') for row in rows] != cases:
        issues.append('Walking craft case order differs')
    if [(marker, value.get('case')) for marker, value in raw] != [
            (marker, case) for case in cases for marker in ('PREPARED', 'WALK_AUTHORITY')]:
        issues.append('Missing, duplicated or reordered walking craft authority')
    all_ids = []
    for case in cases:
        row = next((row for row in rows if row.get('id') == case), {})
        prep = next((value for marker, value in raw if marker == 'PREPARED' and value.get('case') == case), {})
        receipt = next((value for marker, value in raw if marker == 'WALK_AUTHORITY' and value.get('case') == case), {})
        complete = case == 'complete-pinned-tools'; blocked = case == 'walk-pinned-full'
        kept = case == 'walk-editor-keep-saw'; retained = blocked or kept
        expected = dict(status='passed', producer='CraftChainRecipes.enqueue', queueEnabled=enabled,
                        craftProgress=True, tailProgress=complete, tailDiscarded=not complete,
                        nativeStop=not complete, nativeDuration=150, authorityVerified=True, inputReleased=True,
                        consumed=int(complete), materialPresent=not complete, outputs=int(complete),
                        toolsReturned=1 if retained else 2, fullOrigin=blocked)
        if not craft._matches(row, expected):
            issues.append('Walking craft native effects/progress differ: ' + case)
        if (not _number(row.get('walkDistance')) or (row['walkDistance'] != 0 if complete else row['walkDistance'] < .25)
                or not _number(row.get('walkProgress')) or (row['walkProgress'] != 0 if complete
                        else not 0 < row['walkProgress'] <= .25)):
            issues.append('Walking craft genuine movement/early-stop evidence differs: ' + case)
        if (not craft._prepared_valid(prep, case) or not craft._ids(prep.get('outputBaseline'))
                or len(prep['outputBaseline']) != prep['outputs'] or type(prep.get('playerId')) is not int
                or (prep['playerId'] < 0 if selection['kind'] == 'mp' else prep['playerId'] != -1)):
            issues.append('Walking craft exact preparation differs: ' + case)
        else:
            ids = prep['tools']; returned = ids[1:] if retained else ids
            if not craft._matches(row, dict(toolIds=ids, pickupIds=sorted(ids), returnIds=sorted(returned),
                    materialId=prep['material'], materialCondition=prep['materialCondition'], materialUses=prep['materialUses'],
                    blockedToolId=ids[0] if blocked else False)):
                issues.append('Walking craft exact paid pickup/return identities differ: ' + case)
            if enabled:
                if not craft._matches(row, dict(instantActions=False, pauseOnFocusLoss=False,
                                               craftChainsEnabled=True, foreignReturnProvider=False)):
                    issues.append('Walking craft native controls differ: ' + case)
                trace = row.get('eventTrace')
                required = ['pickup-saw', 'pickup-drill', 'craft-progress'] + (['keep-saw'] if kept else []) + [
                    'walk-input', 'native-stop'] + (['return-drill'] if kept else ['return-saw', 'return-drill'])
                if (type(trace) is not list or any(type(event) is not str for event in trace)
                        or sorted(trace) != sorted(required)):
                    issues.append('Walking craft exact event trace differs: ' + case)
                else:
                    before = lambda left, right: trace.index(left) < trace.index(right)
                    ordered = (all(before(pickup, 'craft-progress') for pickup in ('pickup-saw', 'pickup-drill'))
                               and before('craft-progress', 'walk-input') and before('walk-input', 'native-stop')
                               and all(before('native-stop', event) for event in required if event.startswith('return-')))
                    if kept:
                        ordered = ordered and before('craft-progress', 'keep-saw') and before('keep-saw', 'walk-input')
                    if not ordered:
                        issues.append('Walking craft pickup/craft/Keep/walk/stop/return order differs: ' + case)
                if kept:
                    if (not craft._matches(row, dict(keptId=ids[0], keptSourceId=prep['bags'][0], siblingId=ids[1],
                            siblingSourceId=prep['bags'][1], keepSucceeded=True, keptRowPending=True, keptRowRemoved=True,
                            siblingPreserved=True, craftPreservedAfterKeep=True))
                            or not _number(row.get('keepProgress')) or not _number(row.get('walkProgress'))
                            or not 0 < row['keepProgress'] <= row['walkProgress']):
                        issues.append('Walking craft exact pending saw Keep differs: ' + case)
            starts = row.get('returnStarts')
            if not craft._ids(starts) or sorted(starts or []) != sorted(returned):
                issues.append('Walking craft actual return starts differ or repeated: ' + case)
            resources = [dict(meta, sourceId=prep['bags'][i], sourceCount=int(not retained or i != 0),
                              rootCount=int(retained and i == 0)) for i, meta in enumerate(prep['toolMeta'])]
            if not craft._same(row.get('resources'), resources):
                issues.append('Walking craft original bag/tool conservation differs: ' + case)
            spare_ids = []
            for spare in prep.get('sparePlanks', []) if type(prep.get('sparePlanks')) is list else []:
                if (type(spare) is not dict or set(spare) != {'id', 'condition', 'uses'}
                        or any(type(spare.get(key)) is not int for key in ('id', 'condition', 'uses'))):
                    issues.append('Walking craft spare input metadata differs: ' + case)
                else:
                    spare_ids.append(spare['id'])
            if type(prep.get('sparePlanks')) is not list or not craft._same(row.get('sparePlanks'), prep['sparePlanks']):
                issues.append('Walking craft spare input conservation differs: ' + case)
            output_ids = row.get('outputIds')
            if not craft._ids(output_ids, int(complete)):
                issues.append('Walking craft output identity differs: ' + case)
                output_ids = []
            all_ids += ids + prep['bags'] + [prep['material'], prep['book']] + output_ids
            if not craft._ids(ids + prep['bags'] + [prep['material'], prep['book']] + prep['outputBaseline'] + spare_ids + output_ids):
                issues.append('Walking craft identities overlap: ' + case)
        if (set(receipt) != {'case', *RECEIPT_KEYS}
                or not craft._matches(row, {key: receipt.get(key) for key in RECEIPT_KEYS})):
            issues.append('Walking craft client/authority differs: ' + case)
        outcomes.append(dict(actor='client1', case=case, outcome={key: row.get(key) for key in RECEIPT_KEYS +
                        ('pickupIds', 'returnIds', 'returnStarts', 'nativeStop', 'walkDistance', 'walkProgress',
                         'queueEnabled', 'eventTrace', 'keptId', 'keptSourceId', 'keepSucceeded', 'keptRowPending',
                         'keptRowRemoved', 'siblingPreserved', 'craftPreservedAfterKeep', 'keepProgress')}))
    if not craft._ids(all_ids):
        issues.append('Walking craft prepared/output IDs overlap between cases')
    if '[QUEUE_TEST] FAIL ' in text or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Walking craft fixture failed')
    for row in outcomes:
        row.update(status='failed' if issues else 'passed', reason='; '.join(issues))
    return dict(issues=issues, outcomes=outcomes, evidence={'limits': [
        'Programmatic real chain producer; disposable GameKeyboard input causes actual native walking and unmodified engine stop.',
        ('Queue editor is on; Keep uses ActionQueue.cancel on the exact pending saw row before genuine movement.' if enabled else
         'Queue editor remains off.') + ' Movement discards the native reader tail; exact paid tools and original bag endpoints are authoritative.',
        'Native transfer progress plus exact authoritative final identity/condition/uses; no physical keyboard, rendering or WAN claim.']})
