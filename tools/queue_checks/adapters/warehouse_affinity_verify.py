"""Exact peer replacement and visible-personal quick-transfer regression."""
from pathlib import Path

from . import warehouse_workload_verify as V

STEPS = ('initial', 'peer-replace', 'personal-quick')
ensure, require, ids, number, one = V.ensure, V.require, V.ids, V.number, V.one


def endpoints(phase, step):
    result = {row['id']: row['initialEndpoint'] for row in phase['items']}
    if step != 'initial':
        result[phase['replacementSourceId']] = 'client2'
        result[phase['replacementId']] = 'crate3'
    if step == 'personal-quick':
        if phase.get('affinityOutcome') == 'blocked':
            require(phase, oldDestination='client1')
        elif phase.get('affinityOutcome') == 'fresh':
            require(phase, oldDestination='client1'); result[phase['newCandidateId']] = 'crate3'
        else:
            require(phase, affinityOutcome='stale')
            ensure(phase.get('oldDestination') in [f'crate{i}' for i in range(1, 13)], 'foreign stale destination')
            result[phase['oldCandidateId']] = phase['oldDestination']
    return result


def phase_meta(phase, token, index, physical=False):
    require(phase, token=token, index=index, mode='clean', phaseToken=f'{token}:{index}',
            affinityKind=('type', 'category')[(index-1) % 2], outputIds=[])
    if physical:
        require(phase, transferMethod='1' if index <= 2 else '2')
    rows = phase['items']; ensure(type(rows) is list and len(rows) == 15, 'wrong affinity seed cohort')
    meta = {row['id']: row for row in rows}; ids([row['id'] for row in rows], 15)
    for row in rows:
        ensure(all(type(row[key]) is str and bool(row[key]) for key in ('ft', 'key', 'cat', 'initialEndpoint')), 'missing affinity metadata')
    for field, kind, where in [('replacementSourceId', 'Base.Bandage', 'crate3'),
                               ('replacementId', 'Base.Screwdriver', 'client2'),
                               ('oldCandidateId', 'Base.Bandage', 'client1'),
                               ('newCandidateId', 'Base.Screwdriver', 'client1')]:
        require(meta[phase[field]], ft=kind, initialEndpoint=where)
    ensure(phase['oldCategory'] != phase['newCategory'], 'category probe does not discriminate')
    for field in ('replacementSourceId', 'oldCandidateId'):
        ensure(meta[phase[field]]['cat'] == phase['oldCategory'], 'old raw category differs from native metadata')
    for field in ('replacementId', 'newCandidateId'):
        ensure(meta[phase[field]]['cat'] == phase['newCategory'], 'new raw category differs from native metadata')
    for slot in range(1, 13):
        stock = [row for row in rows if row['initialEndpoint'] == f'crate{slot}']
        ensure(len(stock) == 1, 'affinity stock is not one item per crate')
        if slot != 3:
            ensure(stock[0]['cat'] not in (phase['oldCategory'], phase['newCategory']), 'other stock masks category change')
    return meta


def snapshot(row, phase, step, descriptors, originals, role):
    expected = endpoints(phase, step) if phase else {}
    V.snapshot(row, phase, step, descriptors, originals, role, expected=expected, metadata=role == 'server')
    if step == 'personal-quick':
        require(row, affinityOutcome=phase['affinityOutcome'], oldDestination=phase['oldDestination'])


def aggregate(row, phase, step, alternate=None, raw=False):
    require(row, nativeAggregate=True)
    slots = set(ids(row['discoveredSlots'])); ensure(3 in slots and slots <= set(range(1, 13)), 'affinity aggregate omitted source/has foreign source')
    sources = {f'crate{slot}' for slot in slots}
    expected = {key for key, where in endpoints(phase, step).items() if where in sources}
    actual = set(ids(row['actualIds'])); declared = set(ids(row['expectedIds']))
    alternatives = [expected]
    if alternate:
        alternatives.append({key for key, where in endpoints(phase, alternate).items() if where in sources})
    ensure(declared in alternatives and actual <= {item['id'] for item in phase['items']}, 'raw aggregate cohort/physical expectation differs')
    require(row, fresh=actual == declared)
    if raw:
        entries = row['items']; ensure(type(entries) is list and set(ids([item['id'] for item in entries])) == actual, 'missing raw affinity item projections')
        meta = {item['id']: item for item in phase['items']}
        for item in entries:
            require(item, ft=meta[item['id']]['ft'])
            ensure(type(item['rawCategory']) is str and bool(item['rawCategory']), 'missing handler raw category')


def physical_brackets(proof, phase):
    """Validate the selected physical stock independently of aggregate discovery."""
    meta = {item['id']: item for item in phase['items']}
    kind = phase['affinityKind']
    matches = []
    for bracket, step in (('physicalBefore', 'peer-replace'), ('physicalAfter', 'personal-quick')):
        entries = proof[bracket]
        expected = {key for key, where in endpoints(phase, step).items() if where == 'crate3'}
        alternatives = [expected]
        if bracket == 'physicalAfter':
            alternatives.append({phase['replacementId']})
        ensure(type(entries) is list and set(ids([item['id'] for item in entries])) in alternatives,
               'physical stock bracket IDs differ')
        for item in entries:
            require(item, ft=meta[item['id']]['ft'])
            ensure(type(item['rawCategory']) is str and bool(item['rawCategory']), 'missing physical raw category')
        keys = {item['ft'] if kind == 'type' else item['rawCategory'] for item in entries}
        matches.append({phase[label+'CandidateId'] for label in ('old', 'new')
                        if (meta[phase[label+'CandidateId']]['ft'] if kind == 'type' else proof[label+'Category']) in keys})
    keys = [item['ft'] if kind == 'type' else item['rawCategory'] for item in proof['physicalBefore']]
    for label in ('Old', 'New'):
        candidate = phase['oldCandidateId' if label == 'Old' else 'newCandidateId']
        key = meta[candidate]['ft'] if kind == 'type' else proof[label.lower()+'Category']
        require(proof, **{'physical'+label+'Affinity': keys.count(key)})
    if phase['affinityOutcome'] == 'fresh':
        ensure({phase['newCandidateId']} in matches, 'selected singleton has no matching physical affinity bracket')
    elif phase['affinityOutcome'] == 'blocked':
        require(phase, affinityKind='category')
        ensure(matches == [set(), set()], 'blocked physical callback has an affinity match')


def actions(row, phase, step, physical=False):
    current = [a for a in row['records'] if a['step'] == step]
    if physical:
        ensure(current == row['records'], 'physical action receipt contains another step')
    for action in current:
        require(action, sourceMethodsUnchanged=True)
        ensure(action['type'] in ('ISInventoryTransferAction', 'ISWalkToTimedAction'), 'unexpected affinity action')
        number(action['duration']); number(action['progressSamples'], 0)
        if 'transactionDuration' in action:
            number(action['transactionDuration'], .000001); number(action['transactionId'], 1)
    actual = [(a['id'], a['source'], a['destination']) for a in current if a['type'] == 'ISInventoryTransferAction']
    expected = [(phase['replacementSourceId'], 'crate3', 'client2'), (phase['replacementId'], 'client2', 'crate3')]
    if step == 'personal-quick':
        blocked = phase['affinityOutcome'] == 'blocked'
        selected = None if blocked else phase['newCandidateId'] if phase['affinityOutcome'] == 'fresh' else phase['oldCandidateId']
        expected = [] if blocked else [(selected, 'client1', 'crate3' if phase['affinityOutcome'] == 'fresh' else phase['oldDestination'])]
        proof = row['quick']; kind = phase['affinityKind']
        require(proof, dispatched=True, installedButton=True, kind=kind, source='client1',
                oldCandidateId=phase['oldCandidateId'], newCandidateId=phase['newCandidateId'],
                physicalOld=0, physicalNew=1, personalVisible=True, hiddenBefore=True, hiddenAfter=True,
                oldEligible=physical or not blocked, newEligible=physical or not blocked,
                targetOldAllowed=physical or not blocked, targetNewAllowed=physical or not blocked,
                physicalOldAllowed=True, physicalNewAllowed=True, physicalOldEligible=True, physicalNewEligible=True,
                oldFavorite=False, newFavorite=False, oldEquipped=False, newEquipped=False, oldHotbar=False, newHotbar=False,
                targetType='crate' if physical else 'proximityInv', targetCapacity=100 if physical else 0,
                transferMethod=phase['transferMethod'] if physical else '1', buttonLayout='2',
                callback='onTransferByNameClick' if kind == 'type' else 'onTransferByCategoryClick')
        if physical:
            require(proof, targetMode='physical')
            ensure(proof.get('targetOnlyAcceptCategory') is None, 'physical target category restriction differs')
            number(proof['completionTicks'], 3)
            number(proof['completionFrames'], 3); number(proof['completionMs'], 500)
            physical_brackets(proof, phase)
        else:
            require(proof, targetOnlyAcceptCategory='none')
        number(proof['physicalOldAffinity'], 0); number(proof['physicalNewAffinity'], 0)
        if blocked:
            ensure(proof.get('selectedId') is None and row['records'] == [], 'blocked aggregate callback queued an action/selected an item')
            number(proof['completionFrames'], 3); number(proof['completionMs'], 500)
        else:
            require(proof, selectedId=selected)
            if not physical:
                require(proof, physicalOldAffinity=0, physicalNewAffinity=1)
        ensure(proof['oldCategory'] == phase['oldCategory'] and proof['newCategory'] == phase['newCategory'], 'quick raw categories changed')
        aggregate(proof['before'], phase, 'peer-replace', raw=True)
        aggregate(proof['after'], phase, 'peer-replace', 'personal-quick', raw=True)
        meta = {item['id']: item for item in phase['items']}
        matches = []
        for bracket in ('before', 'after'):
            keys = {item['ft'] if kind == 'type' else item['rawCategory'] for item in proof[bracket]['items']}
            admitted = set()
            for candidate, category in ((phase['oldCandidateId'], proof['oldCategory']), (phase['newCandidateId'], proof['newCategory'])):
                if (meta[candidate]['ft'] if kind == 'type' else category) in keys:
                    admitted.add(candidate)
            matches.append(admitted)
        # The callback may legitimately freshen discovery. These observations
        # bracket the call; they do not pretend to instrument its internal read.
        if not blocked and not physical:
            ensure({selected} in matches, 'selected singleton has no matching raw affinity bracket')
    ensure(actual == expected, 'quick/peer transfer IDs or endpoints differ')


def verify(root, case='hidden-affinity'):
    ensure(case in ('hidden-affinity', 'physical-affinity'), 'unknown affinity case')
    physical = case == 'physical-affinity'
    indices = range(1, 5 if physical else 3)
    phase_count = len(indices)
    root = Path(root)
    rows = {role: V.records((root / (role+'-launch.log')).read_text(errors='replace'), role, case)
            for role in ('server', 'client1', 'client2')}
    server = rows['server']; setup = one(server, 'SETUP'); descriptors = setup['ids']; token = descriptors['token']
    originals = {role: ids(descriptors['originalRootIds'][role]) for role in ('client1', 'client2')}
    ids(originals['client1'] + originals['client2'])
    peers = setup['onlineIds']; ids([peers['client1'], peers['client2']], 2)
    ensure(len(descriptors['crates']) == 12 and len(set(d['id'] for d in descriptors['crates'])) == 12, 'world descriptors duplicate/missing')
    expected_server = ['SETUP'] + (['SEED', 'SEEN', 'SEEN'] + ['GO', 'AUTHORITY', 'SEEN', 'SEEN']*2 + ['RELEASE'])*phase_count + ['RESTORED', 'COMPLETE']
    ensure([event for event, _ in server] == expected_server, 'affinity server lifecycle order/duplicates differ')
    for _, row in server:
        require(row, token=token)
    phases = {}
    for index in indices:
        selected = [(event, row) for event, row in server if row.get('index') == index and event in ('SEED', 'GO', 'AUTHORITY', 'SEEN', 'RELEASE')]
        seed = one(selected, 'SEED'); base = seed['phase']; meta = phase_meta(base, token, index, physical)
        for event, row in selected:
            require(row, token=token, index=index, phaseToken=f'{token}:{index}')
            if event != 'RELEASE':
                require(row, paneMode='clean')
        ensure(not set(meta).intersection(originals['client1'] + originals['client2']), 'affinity IDs alias originals')
        readiness = seed['readiness']; ensure(set(readiness) == {'client1', 'client2'}, 'missing peer placement readiness')
        for role, proof in readiness.items():
            require(proof, deadlineMs=15000, onlineId=peers[role])
            ensure(0 <= number(proof['waitMs']) < 15000 and proof['confirmedAt']-proof['requestedAt'] == proof['waitMs'], 'unsettled peer placement')
            origin = descriptors['actorOrigin']
            ensure(all(abs(proof[axis]-origin[axis]-.5) <= 1 for axis in ('x', 'y')) and proof['z'] == origin['z'], 'peer placement outside fixture')
        snapshot(seed['snapshot'], base, 'initial', descriptors, originals, 'server')
        by_step = {'initial': (base, seed['snapshot'])}
        for step in STEPS:
            observed = [row for event, row in selected if event == 'SEEN' and row['step'] == step]
            ensure(sorted(row['observer'] for row in observed) == ['client1', 'client2'], 'missing/duplicate peer observation')
            if step == 'initial':
                continue
            branch = [(event, row) for event, row in selected if row.get('step') == step]
            go, authority = one(branch, 'GO'), one(branch, 'AUTHORITY')
            require(go, actor='client1' if step == 'personal-quick' else 'client2')
            phase = authority['phase']; ensure(phase_meta(phase, token, index, physical) == meta, 'seeded affinity metadata changed')
            for key in ('replacementSourceId', 'replacementId', 'oldCandidateId', 'newCandidateId', 'oldCategory', 'newCategory'):
                ensure(phase[key] == base[key], 'affinity phase identity changed')
            snapshot(authority['snapshot'], phase, step, descriptors, originals, 'server')
            by_step[step] = (phase, authority['snapshot'])
        release = one(selected, 'RELEASE'); final = by_step['personal-quick'][0]
        require(release, ownedRemaining=0, consumedIds=[], affinityOutcome=final['affinityOutcome'], oldDestination=final['oldDestination'])
        ensure(set(ids(release['removedIds'], 15)) == set(meta), 'affinity cleanup cohort differs')
        journal = release['cleanupJournal']; require(journal, removalCalls=15, noticeAttempts=15, recoveries=[])
        ensure(ids(journal['removedIds'], 15) == sorted(meta), 'affinity cleanup journal differs')
        ensure(release['originalRootIds'] == originals, 'cleanup originals changed')
        snapshot(release['snapshot'], None, None, descriptors, originals, 'server')
        phases[index] = {'steps': by_step, 'release': release}
    restored = one(server, 'RESTORED'); require(restored, removedCrates=12, ownedAbsent=True, ownedRemaining=0)
    ensure(restored['originalRootIds'] == originals and len(restored['crates']) == 12, 'world/original cleanup differs')
    for before, after in zip(descriptors['crates'], restored['crates']):
        ensure(all(after[key] == value for key, value in before.items()) and number(after['afterIndex']) < 0, 'world cleanup changed identity/survives')
    snapshot(restored['snapshot'], None, None, descriptors, originals, 'server')
    require(one(server, 'COMPLETE'), phases=phase_count, restored=True)
    for role in ('client1', 'client2'):
        client = rows[role]; baseline = one(client, 'BASELINE')
        expected_client = ['BASELINE', 'SETUP']
        for _ in indices:
            expected_client += ['MODE']
            for step in STEPS:
                if (role == 'client1' and step == 'personal-quick') or (role == 'client2' and step == 'peer-replace'):
                    expected_client += ['ACTIONS']
                expected_client += ['HIDDEN', 'SNAPSHOT']
            expected_client += ['RELEASE']
        expected_client += ['RESTORED', 'COMPLETE']
        ensure([event for event, _ in client] == expected_client, 'affinity client lifecycle order/duplicates differ')
        require(baseline['original'], identity=True, payload=True, equipment=True); number(baseline['stableSamples'], 3)
        ensure(set(originals[role]) <= set(ids(baseline['original']['ids'])), 'baseline omitted original root IDs')
        for name in ('transferMethod', 'transferButtonLayout'):
            ensure(type(baseline['affinityOptions'][name]) is int and baseline['affinityOptions'][name] in (1, 2), 'invalid original quick option')
        ensure(one(client, 'SETUP')['ids'] == descriptors, 'client world descriptors differ')
        for event, row in client:
            if event != 'BASELINE':
                require(row, token=token)
        for index in indices:
            selected = [(event, row) for event, row in client if row.get('index') == index and event in ('MODE', 'ACTIONS', 'HIDDEN', 'SNAPSHOT', 'RELEASE')]
            V.position(one(selected, 'MODE')['placement'])
            for event, row in selected:
                require(row, token=token, index=index, paneMode='clean')
                if event != 'MODE':
                    require(row, phaseToken=f'{token}:{index}')
            for step in STEPS:
                branch = [(event, row) for event, row in selected if row.get('step') == step and event != 'RELEASE']
                phase, authority = phases[index]['steps'][step]
                hidden = one(branch, 'HIDDEN'); observed = one(branch, 'SNAPSHOT')
                if physical and step == 'personal-quick':
                    # Native transfer can explicitly refresh its destination;
                    # this active callback is not an idle deferred-row claim.
                    for side in ('before', 'after'):
                        require(hidden[side], visible=False)
                        number(hidden[side]['nativeBuilds'], 0)
                        if 'rowsPending' in hidden[side]:
                            ensure(type(hidden[side]['rowsPending']) is bool, 'invalid hidden pending flag')
                    ensure(hidden['after']['nativeBuilds'] >= hidden['before']['nativeBuilds'], 'hidden build counter regressed during physical callback')
                else:
                    require(hidden['before'], visible=False, rowsPending=True); require(hidden['after'], visible=False, rowsPending=True)
                    ensure(hidden['before']['nativeBuilds'] == hidden['after']['nativeBuilds'], 'hidden rows rebuilt during affinity probe')
                number(hidden['samples'], 1)
                snapshot(observed['native'], phase, step, descriptors, originals, role)
                if physical:
                    for item in observed['native']['items']:
                        category = item['rawCategory']
                        ensure(type(category) is str and bool(category), 'missing physical client raw category')
                aggregate(observed['aggregateBefore'], phase, step)
                ensure(set(ids(hidden['after']['rawAggregateIds'])) == set(ids(observed['aggregateBefore']['actualIds'])), 'hidden aggregate changed before observation')
                if step != 'initial':
                    ensure(observed['authority'] == authority, 'client referenced another authority effect')
                    proof = observed['affinity']; require(proof, kind=phase['affinityKind'], personalVisible=True, lootHidden=True, forcedRefresh=False)
                    number(proof['naturalFrames'], 3); number(proof['settledMs'], 500)
                    ensure(proof['oldCategory'] == phase['oldCategory'] and proof['newCategory'] == phase['newCategory'], 'observed raw categories differ')
                    aggregate(proof['aggregate'], phase, step, raw=True)
                    ensure(type(proof['samples']) is list and 1 <= len(proof['samples']) <= 16, 'missing/bloated natural aggregate samples')
                    for sample in proof['samples']:
                        number(sample['frame'], 0); number(sample['elapsedMs'], 0)
                        # Samples start only after replacement physically converges.
                        evidence = dict(sample, nativeAggregate=True, discoveredSlots=proof['aggregate']['discoveredSlots'])
                        aggregate(evidence, phase, 'peer-replace', raw=True)
                if (role == 'client1' and step == 'personal-quick') or (role == 'client2' and step == 'peer-replace'):
                    action_row = one(branch, 'ACTIONS')
                    actions(action_row, phase, step, physical)
            release = one(selected, 'RELEASE'); require(release, absent=True)
            ensure(release['receipt'] == phases[index]['release'] and release['original'] == baseline['original'], 'client release/originals differ')
        final = one(client, 'RESTORED'); require(final, ownedAbsent=True)
        ensure(final['original'] == final['actual'] == baseline['original'] and final['authority'] == restored, 'client final ownership/originals differ')
        V.position(final['positionProof'], baseline['position']); V.restored_ui(final['uiProof'])
        for name in ('transferMethod', 'transferButtonLayout'):
            option = final['affinityOptions'][name]; ensure(option['expected'] == option['actual'] == baseline['affinityOptions'][name], 'quick option not restored')
        require(one(client, 'COMPLETE'), phases=phase_count, restored=True)
    outcomes = [phases[index]['steps']['personal-quick'][0]['affinityOutcome'] for index in indices]
    ensure(outcomes == (['fresh']*4 if physical else ['blocked', 'blocked']), 'native personal quick affinity outcomes: ' + repr(outcomes))
    limits = ('Visible personal CleanUI split callbacks use physical crate affinity for both transfer methods; no physical mouse input, vanilla toolbar or performance claim.' if physical else
              'Visible personal CleanUI split buttons preserve BC aggregate admission restrictions; no personal quick transfer, physical mouse input, vanilla toolbar or performance claim.')
    return {'phases': phase_count, 'peers': 2, 'steps': list(STEPS), 'outcomes': outcomes, 'limits': [limits]}
