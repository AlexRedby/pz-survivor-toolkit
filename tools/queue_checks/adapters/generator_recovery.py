"""Normal grooming producer, automatic generator recovery, and real peer contention."""
from pathlib import Path
import shutil
import zipfile

from .. import receipts
from .razor_restoration import MODS

SUITE = 'generator-recovery'
PREFIX = '[GENERATOR_RECOVERY] '
CASES = ['auto-return', 'new-primary-intent', 'cancel-active', 'peer-pickup', 'owner-pickup-first']
PEER_CASES = ['peer-pickup', 'owner-pickup-first']


def definitions():
    return {SUITE: dict(status='ready', clients=1, default_mods=list(MODS), cases=[
        dict(id=case, kinds=['mp'] if case in PEER_CASES else ['sp', 'mp'],
             clients=2 if case in PEER_CASES else 1,
             languages=['EN', 'RU'] if case in PEER_CASES else ['EN'],
             modes=['toolkit'], producer='fixture', capability='effect') for case in CASES])}


def validate(selection):
    cases = selection.get('cases')
    peer = type(cases) is list and bool(cases) and all(case in PEER_CASES for case in cases)
    options = selection.get('options', {})
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or any(case in PEER_CASES for case in cases) and not peer
            or selection.get('kind') not in (['mp'] if peer else ['sp', 'mp'])
            or selection.get('mode') != 'toolkit' or selection.get('clients') != (2 if peer else 1)
            or type(selection.get('clients')) is not int
            or selection.get('languages') != (['EN', 'RU'] if peer else ['EN'])
            or selection.get('mods') != MODS or options.get('world_template')
            or selection.get('kind') == 'mp' and options.get('mp_host') is not True):
        raise ValueError('Generator recovery requires ordered fresh P4-free SP/menu Host cases; peer orderings require a separate two-client Host lifecycle')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueuePreflight.lua',
            root / 'support/QueueEnergyPlacement.lua', Path(__file__), Path(receipts.__file__),
            Path(project) / 'tests/test_queue_generator_recovery.py']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    jar = Path(locations['PZToolkitJavaPatches']) / '42/media/java/PZToolkitJavaPatches.jar'
    with zipfile.ZipFile(jar) as archive:
        if 'net/alexredby/pztoolkitjavapatches/GeneratorDropObservation$ItemConversion.class' not in archive.namelist():
            raise ValueError('Generator recovery requires the selected native conversion observer')
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for relative in ['startup/client/ZZStartup.lua', 'startup/server/ZZStartupServer.lua',
                         'health/shared/QueueHealthEvents.lua']:
            source = root / relative
            shutil.copy2(source, lua / source.parent.name / source.name)
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL generator-recovery'], sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    try:
        return role.startswith('client') and receipts.records(text, PREFIX, 'COMPLETE') == [dict(cases=selection['cases'])]
    except (ValueError, TypeError):
        return False


def result_errors(row, case, kind):
    errors = []
    try:
        peer = case in PEER_CASES
        peer_wins = case == 'peer-pickup'
        recovered = case in ('auto-return', 'cancel-active', 'owner-pickup-first')
        output = recovered or peer
        exact = dict(case=case, authority=True, producer='ISCharacterScreen.onTrimBeard',
            type='Base.Generator', condition=73, fuel=7.5, sourceFavorite=True,
            outputFavorite=False if output else None, originalAbsent=True, decoyPresent=True,
            targetPresent=case == 'new-primary-intent', ownerBothHands=recovered,
            ownerHasRazor=peer_wins, ownerHasReplacement=case == 'new-primary-intent',
            beard='LongScruffy' if case == 'cancel-active' else 'Moustache', tailComplete=True,
            peerBothHands=peer_wins, razorReturned=recovered, razorInRoot=not recovered, bagCanonical=True)
        for key, value in exact.items():
            if row.get(key) != value or type(row.get(key)) is not type(value):
                errors.append('Incorrect authority ' + key)
        identities = ['originalId', 'razorId', 'replacementId', 'tailId', 'ownerOnlineId', 'decoyIndex']
        if output: identities.append('outputId')
        if peer: identities.extend(['pickerOnlineId', 'peerStartedAt'])
        if any(type(row.get(key)) is not int for key in identities):
            errors.append('Missing exact authority identities')
        if output and row['outputId'] in [row[key] for key in ('originalId', 'razorId', 'replacementId', 'tailId')]:
            errors.append('Native generator output reused an input identity')
        if peer and row['ownerOnlineId'] == row['pickerOnlineId']:
            errors.append('Peer is not a distinct authority actor')
        if not output and row.get('outputId') is not None:
            errors.append('Unexpected output for superseding primary intent')
        if not row.get('dropObserved') or not row.get('trimStarted'):
            errors.append('Missing native drop/grooming authority boundary')
    except (KeyError, TypeError, ValueError) as error:
        errors.append('Malformed authority receipt: ' + str(error))
    return errors


def evidence_errors(row, case):
    errors = []
    try:
        expected = dict(case=case, producer='ISCharacterScreen.onTrimBeard', nativeCallbacksSame=True,
            producerSameOperation=True, independentTail=True, trimProgress=True,
            canceled=case == 'cancel-active', explicitIntent=case == 'new-primary-intent',
            peerPickup=case in PEER_CASES, recoveryProgress=case != 'new-primary-intent',
            tailProgress=True, tailAfterCleanup=True, noP4=True)
        for key, value in expected.items():
            if row.get(key) != value or type(row.get(key)) is not type(value):
                errors.append('Incorrect producer evidence ' + key)
        actions = row['actions']
        types = [action['type'] for action in actions]
        transfers = [action for action in actions if action['type'] == 'ISInventoryTransferAction']
        if len(transfers) != (2 if case in ('auto-return', 'cancel-active', 'owner-pickup-first') else 1):
            errors.append('Borrowed razor pickup/return topology differs')
        if types.count('ISTrimBeard') != 1 or types.count('ISReadABook') != 1:
            errors.append('Native producer/tail action identity differs')
        wanted = 0 if case == 'new-primary-intent' else 1
        if types.count('PZSurvivorToolkitGeneratorRecovery') != wanted:
            errors.append('Automatic generator pickup topology differs')
        if any(type(action.get('ref')) is not str or not action['ref'] for action in actions):
            errors.append('Native action reference missing')
        if len({action['ref'] for action in actions}) != len(actions):
            errors.append('Native action identity duplicated')
        for action in actions:
            if action['type'] in ('ISTrimBeard', 'ISReadABook', 'PZSurvivorToolkitGeneratorRecovery'):
                duration = 300 if action['type'] == 'ISTrimBeard' else 100 if action['type'] == 'PZSurvivorToolkitGeneratorRecovery' else None
                if duration and action.get('duration') != duration:
                    errors.append('Native duration differs: ' + action['type'])
                if not action.get('progress') or not action.get('native'):
                    errors.append('Native action progress/allocation missing: ' + action['type'])
    except (KeyError, TypeError, ValueError) as error:
        errors.append('Malformed producer evidence: ' + str(error))
    return errors


def binding_errors(evidence, authority):
    errors = []
    try:
        for action in evidence['actions']:
            if action['type'] == 'PZSurvivorToolkitGeneratorRecovery':
                if (type(action.get('sourceID')) is not int or action['sourceID'] != authority['originalId']
                        or type(action.get('toolID')) is not int or action['toolID'] != authority['razorId']
                        or type(action.get('episode')) is not int or action['episode'] < 1):
                    errors.append('AUTO recovery wire identity differs from exact seeded source/tool episode')
            if action['type'] == 'ISInventoryTransferAction' and action.get('itemId') != authority['razorId']:
                errors.append('Native borrowed razor transfer changed item identity')
    except (KeyError, TypeError, ValueError) as error:
        errors.append('Malformed AUTO identity binding: ' + str(error))
    return errors


def peer_errors(row, owner):
    errors = []
    case = row.get('case')
    if (case not in PEER_CASES or row.get('type') != 'ISTakeGenerator'
            or row.get('duration') != 100 or row.get('progress') is not True
            or row.get('native') is not True or row.get('normalProducer') is not True
            or row.get('outputHeld') is not (case == 'peer-pickup')
            or type(row.get('progressDelta')) not in (int, float) or not 0 < row['progressDelta'] < 1):
        errors.append('Second peer native pickup progress/output differs')
    started, progress = owner.get('recoveryStartedAt'), owner.get('recoveryProgressAt')
    peer_started, peer_finished = row.get('startedAt'), row.get('finishedAt')
    if any(type(value) is not int for value in (started, progress, peer_started, peer_finished)):
        errors.append('Native pickup overlap timestamps missing')
    elif case == 'peer-pickup':
        if not peer_started < started <= progress < peer_finished:
            errors.append('Peer-first native pickup did not overlap positive AUTO recovery progress')
    else:
        finished = owner.get('recoveryFinishedAt')
        if type(finished) is not int or not started <= progress < peer_started < finished:
            errors.append('AUTO-first recovery did not overlap the later normal peer pickup')
    return errors


def verify(root, selection, catalog):
    roles = ['client1', 'client2'] if selection['clients'] == 2 else ['client1']
    errors = []
    try:
        logs = {role: (Path(root) / (role + '-launch.log')).read_text(errors='replace')
                for role in roles + (['server'] if selection['kind'] == 'mp' else [])}
        authority = 'server' if selection['kind'] == 'mp' else 'client1'
        authority_rows = receipts.records(logs[authority], PREFIX, 'AUTHORITY')
        owner_rows = receipts.records(logs['client1'], PREFIX, 'EVIDENCE')
        if len(authority_rows) == len(owner_rows):
            for evidence, result in zip(owner_rows, authority_rows):
                errors.extend(binding_errors(evidence, result))
        for role, log in logs.items():
            if role in roles and not complete(selection, role, log):
                errors.append(role + ': completion missing/duplicated')
            results = receipts.records(log, PREFIX, 'AUTHORITY')
            evidence = receipts.records(log, PREFIX, 'EVIDENCE')
            if role == authority:
                if [row.get('case') for row in results] != selection['cases']:
                    errors.append('Authority cases missing/reordered/duplicated')
                for row in results: errors.extend(result_errors(row, row.get('case'), selection['kind']))
            elif results:
                errors.append('Unexpected replica authority receipt')
            if role == 'client1':
                if [row.get('case') for row in evidence] != selection['cases']:
                    errors.append('Producer cases missing/reordered/duplicated')
                for row in evidence: errors.extend(evidence_errors(row, row.get('case')))
            elif evidence:
                errors.append('Unexpected non-owner producer evidence')
            peer = receipts.records(log, PREFIX, 'PEER_PICKUP')
            if role == 'client2' and all(case in PEER_CASES for case in selection['cases']):
                if [row.get('case') for row in peer] != selection['cases']:
                    errors.append('Second-peer native cases missing/reordered/duplicated')
                by_case = {row.get('case'): row for row in receipts.records(logs['client1'], PREFIX, 'EVIDENCE')}
                authority_by_case = {row.get('case'): row for row in authority_rows}
                for row in peer:
                    errors.extend(peer_errors(row, by_case.get(row.get('case'), {})))
                    if row.get('startedAt') != authority_by_case.get(row.get('case'), {}).get('peerStartedAt'):
                        errors.append('Peer positive-progress source time differs from authority receipt')
            elif peer:
                errors.append('Unexpected peer pickup evidence')
    except (KeyError, OSError, ValueError, TypeError) as error:
        errors.append(str(error))
    return dict(issues=errors, outcomes=[dict(actor=role, case=case,
        status='failed' if errors else 'passed', reason='; '.join(errors))
        for role in roles for case in selection['cases']])
