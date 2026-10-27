"""Actual native pet animation stop, explicit native clear and invalid distance.

The authority oracle is IsoAnimal.petAnimal's XP event and raw cooldown effect, not a
claim about Java invocation counts. Lure and mid-animation target loss are outside
this bounded fixture. Native-reset controls can correlate terminal wire messages
to a sealed Started receipt, but reset correctly revokes terminal editing rights.
"""
import json
import math
from pathlib import Path
import re
import shutil
import struct
from .tv_controls import MODS

CASES = ['pet-success', 'pet-cancel', 'pet-invalid']
PREFIX = '[ANIMAL_TERMINAL] '


def definitions():
    return {'animal-terminal': dict(status='ready', clients=1, default_mods=list(MODS),
        scenario_actions={'native-pet': dict(
            scope='Actual AnimalContextMenu pet approach and native pet animation/forceStop; native queue clear during started animation; actual constructor rejected by distant-animal isValid before pet start. Fresh full-selected-pack SP/menu Host with ordinary 400 duration. Authority exact native XP event/float32 map delta and raw cooldown oracle; passive acceptance is descriptive and exact independent book; aborted controls demonstrate queue reuse. Host uses sealed Started receipt and correlated terminal wire after reset; only preserved queue retains sealed terminal observation. No lure, mid-animation target loss, or Java invocation-count assertion.',
            checks={'success-empty': {'pet-success': dict(effectsVerified=True, tailCompleted=True)},
                    'success-queued': {'pet-success': dict(effectsVerified=True, originalTailPreserved=True)},
                    'cancel-active': {'pet-cancel': dict(cancelled=True, cleanupVerified=True)},
                    'server-authority': {case: dict(authoritative=True) for case in CASES}},
            toolkit_only=['success-queued'],
            not_applicable={'lost-before-start':'The distant-animal case proves native invalid-start abort and queue reuse; it does not preserve the original unrelated tail.'})},
        cases=[dict(id=case, producer='native-pet', capability='effect', kinds=['sp','mp'], modes=['native','toolkit'], languages=['EN']) for case in CASES])}


def validate(selection):
    if (selection.get('cases') != CASES or selection.get('kind') not in ('sp','mp')
            or selection.get('mode') not in ('native','toolkit') or selection.get('languages') != ['EN']
            or type(selection.get('clients')) is not int or selection['clients'] != 1
            or selection.get('mods') != MODS or selection.get('options', {}).get('world_template')
            or selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Animal terminal requires all three ordered pet cases, fresh full-pack SP/menu Host and one EN client')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root/'animal-terminal').rglob('*.lua')), *sorted((root/'startup').rglob('*.lua')),
            root/'health/shared/QueueHealthEvents.lua', root/'support/QueueEnergyPlacement.lua', Path(__file__).with_name('tv_controls.py')]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client','ZZStartup.lua'), ('server','ZZStartupServer.lua')]:
            shutil.copy2(root/'startup'/side/name, lua/side/name)
        shutil.copy2(root/'health/shared/QueueHealthEvents.lua', lua/'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[ANIMAL_TERMINAL] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL animal-terminal'], sandbox={'Zombies':6, 'MinutesPerPage':2.0})


def raw(text, marker):
    return [json.loads(match[1]) for match in re.finditer(re.escape(PREFIX+marker+' ')+r'([^\n]+)', text)]


def complete(selection, role, text):
    try:
        return role == 'client1' and raw(text, 'COMPLETE') == [{'cases': selection['cases']}]
    except (ValueError, TypeError):
        return False


def number(value):
    return type(value) in (int,float) and math.isfinite(value)


def snapshot(value, ids, final=False, authority=False):
    assert type(value) is dict and value['case'] == ids['case']
    assert type(value['animal']) is int and type(value['online']) is int
    assert value['animal'] == ids['animal']['id'] and value['online'] == ids['animal']['online'] and value['animalType'] == 'hen'
    assert number(value['acceptance']) and 0 <= value['acceptance'] <= 100
    assert number(value['petTimer']) and value['petTimer'] >= 0 and value['cooldownReady'] is (value['petTimer'] <= 0)
    assert type(value['ghost']) is bool and type(value['held']) is bool
    assert number(value['husbandryXP']) and value['husbandryXP'] >= 0 and type(value['husbandryLevel']) is int and 0 <= value['husbandryLevel'] <= 10
    ledger = value['xpLedger']; assert type(ledger) is list
    for i,event in enumerate(ledger,1):
        assert type(event) is dict and event['sequence'] == i and type(event['sequence']) is int
        assert all(number(event[k]) for k in ('at','amount','before','after','petTimer','acceptance'))
        assert event['amount'] > 0 and event['before'] >= 0 and event['after'] > event['before'] and 0 <= event['acceptance'] <= 100
        assert type(event['level']) is int and 0 <= event['level'] <= 10
    assert type(value['cooldownReady']) is bool and type(value['petting']) is bool and isinstance(value['idleAction'], str)
    assert number(value['distance']) and value['distance'] >= 0
    roots = value['rootIds']
    assert type(roots) is list and all(type(v) is int for v in roots) and roots == sorted(set(roots))
    b = value['book']; spec = ids['book']
    assert set(b) == {'id','type','root','pages','itemPages','total'}
    assert type(b['id']) is int and type(b['total']) is int
    assert b['id'] == spec['id'] and b['id'] in roots and b['type'] == spec['type'] and b['root'] is True and b['total'] == spec['total']
    assert all(type(b[k]) is int and 0 <= b[k] <= spec['total'] for k in ('pages','itemPages'))
    if final:
        assert b['pages'] == b['itemPages'] == spec['total'] and value['petting'] is False and value['idleAction'] == ''
    if authority and final:
        initial = ids['baseline']['husbandryXP']
        if ids['case'] == 'pet-success':
            assert len(ledger) == 1 and value['petTimer'] > 0
            event = ledger[0]; adjustment = event['level']*200
            assert event['before'] == initial and event['after'] == struct.unpack('f',struct.pack('f',event['before']+event['amount']))[0]
            assert value['husbandryXP'] == event['after']
            assert event['petTimer'] % 1 == 0 and 15000-adjustment <= event['petTimer'] <= 24999-adjustment
            assert value['petTimer'] <= event['petTimer']
        else:
            assert ledger == [] and value['petTimer'] == 0 and value['husbandryXP'] == initial



def check_case(row, selection, prepared, baseline, verified):
    case = row['id']; ids = row['ids']; mp = selection['kind'] == 'mp'
    preserved = case == 'pet-success' and selection['mode'] == 'toolkit'
    assert row['status'] == 'passed', row.get('reason', 'fixture failed')
    assert ids == prepared and ids['case'] == case and ids['duration'] == 400
    assert type(ids['actor']) is int and type(ids['animal']['id']) is int and type(ids['animal']['online']) is int
    assert ids['animal']['type'] == 'hen' and ids['animal']['breed'] == 'rhodeisland'
    spec = ids['book']; assert set(spec) == {'id','type','total','initial'} and type(spec['id']) is int
    assert spec['type'] == 'Base.BookFirstAid1' and type(spec['total']) is int and spec['total'] > 1 and spec['initial'] == spec['total'] - 1
    assert set(ids['origin']) == {'x','y','z'} and all(type(v) is int for v in ids['origin'].values())
    assert (set(ids.get('gate', {})) == {'id','type','total','initial'}) if case == 'pet-invalid' else 'gate' not in ids
    if case == 'pet-invalid':
        assert ids['gate']['type'] == 'Base.BookCarpentry1' and type(ids['gate']['id']) is int and ids['gate']['id'] != spec['id']
        assert type(ids['gate']['total']) is int and ids['gate']['initial'] == ids['gate']['total'] - 1
    assert row['authorityBaseline'] == baseline and row['receipt'] == verified and verified['baseline'] == baseline and verified['case'] == case
    for value in (ids['baseline'], row['baseline'], baseline):
        snapshot(value, ids)
        assert value['book']['pages'] == value['book']['itemPages'] == spec['initial'] and value['petting'] is False and value['idleAction'] == ''
    assert ids['baseline']['acceptance'] == 40
    assert ids['baseline']['petTimer'] == baseline['petTimer'] == 0 and ids['baseline']['cooldownReady'] is baseline['cooldownReady'] is True
    assert ids['baseline']['xpLedger'] == baseline['xpLedger'] == [] and ids['baseline']['husbandryXP'] == baseline['husbandryXP']
    assert set(ids['placement']) == {'x','y','z'} and all(type(v) is int for v in ids['placement'].values())
    context = ids['xpContext']; assert set(context) == {'boost','bookMultiplier','fast','slow','global','globalToggle','husbandry'}
    assert type(context['boost']) is int and number(context['bookMultiplier']) and all(type(context[k]) is bool for k in ('fast','slow','globalToggle'))
    if case == 'pet-invalid': assert row['baseline']['distance'] >= 3 and baseline['distance'] >= 3
    else: assert row['baseline']['distance'] < 3 and baseline['distance'] < 3
    for value in (row['clientFinal'], verified['final']): snapshot(value, ids, final=True, authority=value is verified['final'])
    assert row['clientFinal']['rootIds'] == row['baseline']['rootIds'] and verified['final']['rootIds'] == baseline['rootIds']
    assert row['nativeMethodsUnchanged'] is True and row['queueIdle'] is True and number(row['settleMilliseconds']) and row['settleMilliseconds'] >= 2000
    assert isinstance(row['limits'], str) and row['limits']
    commands = row['commands']; body = commands['body']; tail = commands['tail']; recovery = commands['recovery']
    assert set(commands) == ({'body','tail','recovery','gate'} if case == 'pet-invalid' else {'body','tail','recovery'})
    assert body['name'] == 'body' and body['type'] == 'ISPetAnimal' and body['duration'] == 400
    assert body['initialValid'] is (case != 'pet-invalid') and body['producer'] == ('native ISPetAnimal constructor' if case == 'pet-invalid' else 'AnimalContextMenu.onPetAnimal')
    assert type(body['starts']) is int and body['starts'] == int(case != 'pet-invalid') and body['started'] is (case != 'pet-invalid')
    if body['started']:
        assert isinstance(body['nativeRef'], str) and body['nativeRef'] and number(body['allocatedAt']) and number(body['startedAt']) and body['allocatedAt'] <= body['startedAt']
    for action in commands.values():
        if action is False: continue
        if 'beginAt' in action:
            timing=action['timing']
            assert timing['constructor']==timing['beforeCreate']==action['duration'] and timing['sampleAt']==action['beginAt']
            assert timing['source']=='ISBaseTimedAction.adjustMaxTime' and number(timing['expectedAdjusted']) and timing['expectedAdjusted']>1
            assert timing['allocated']==timing['expectedAdjusted'] and action['allocatedAt']>=timing['sampleAt']
            assert type(timing['samples']) is list and timing['samples']
            for sample_index,sample in enumerate(timing['samples']):
                assert sample['phase'] in ('allocated','started','stop','perform','complete') and number(sample['at']) and sample['at']>=timing['sampleAt']
                assert number(sample['luaMaxTime']) and sample['luaMaxTime']>1 and number(sample['nativeCurrentTime'])
                # BaseAction initializes currentTime=-2 before native start.
                # Keep that sentinel limited to the first allocation witness.
                if sample['nativeCurrentTime']<0:
                    assert sample_index==0 and sample['phase']=='allocated' and sample['nativeCurrentTime']==-2 and sample['jobDelta']==0
                else:
                    assert sample['nativeCurrentTime']>=0
                assert number(sample['jobDelta']) and sample['jobDelta']>=0
            assert timing['samples'][0]['luaMaxTime']==timing['expectedAdjusted']
        else:
            assert 'timing' not in action
        assert type(action) is dict and type(action['finishes']) is list
        assert all(end['succeeded'] is True and end['phase'] in ('stop','perform','complete') and number(end['at']) for end in action['finishes'])
        for end in action['finishes']: snapshot(end['snapshot'], ids)
    assert all(end['phase'] == 'stop' for end in body['finishes'])
    if case=='pet-invalid':
        # Native allocates then discards this invalid action before start; it
        # never invokes pet stop, so callback absence is part of the proof.
        assert body['finishes']==[] and 'startedAt' not in body
        assert isinstance(body['nativeRef'],str) and body['nativeRef'] and number(body['allocatedAt'])
        assert len(body['timing']['samples'])==1 and body['timing']['samples'][0]['phase']=='allocated'
        assert body['timing']['samples'][0]['nativeCurrentTime']==-2
    else:
        assert len(body['finishes'])==1, 'started native pet stop must occur once'
        assert body['finishes'][0]['snapshot']['petting'] is False and body['finishes'][0]['snapshot']['idleAction']==''
    if mp and body['started']:
        ack = body['ack']
        assert type(ack) is dict and set(ack) == {'kind','transaction','token'} and ack['kind'] == 'ISPetAnimal'
        assert type(ack['transaction']) is int and -128 <= ack['transaction'] <= 127 and ack['transaction'] != 0
        assert isinstance(ack['token'], str) and re.fullmatch(r'[\da-fA-F]{8}(?:-[\da-fA-F]{4}){3}-[\da-fA-F]{12}', ack['token'])
        assert body['terminal'] == body['wireTerminal'] == 'canceled'
        assert body['terminalProof'] == ('sealed-native-receipt' if preserved else 'correlated-wire-after-reset')
    elif not mp:
        assert body['ack'] is False and body['terminal'] is False
    terminal = row['terminal']; snapshot(terminal['snapshot'], ids)
    assert terminal['case'] == case and number(terminal['at']) and terminal['preserved'] is preserved and terminal['originalTailStarted'] is preserved
    assert tail['name'] == 'tail' and tail['type'] == 'ISReadABook' and number(tail['duration']) and tail['duration'] > 1 and tail['started'] is preserved and type(tail['starts']) is int and tail['starts'] == int(preserved)
    if preserved:
        assert recovery is False and terminal['snapshot']['book']['pages'] == spec['total']
    else:
        assert tail['finishes'] == [] and tail['nativeRef'] is False and terminal['snapshot']['book']['pages'] == spec['initial']
        assert recovery['name'] == 'recovery' and recovery['type'] == 'ISReadABook' and recovery['started'] is True and type(recovery['starts']) is int and recovery['starts'] == 1
        assert number(recovery['duration']) and recovery['duration'] > 1 and recovery['beginAt'] >= terminal['at']
    reader = tail if preserved else recovery
    if case=='pet-invalid':
        assert body['allocatedAt']<=terminal['at']<=reader['beginAt']
        assert terminal['snapshot']['xpLedger']==[] and terminal['snapshot']['petTimer']==0 and terminal['snapshot']['husbandryXP']==ids['baseline']['husbandryXP']
        assert terminal['snapshot']['petting'] is False and terminal['snapshot']['idleAction']==''
    else:
        assert body['finishes'][0]['at']<=reader['beginAt']
    assert reader['before']['book']['pages']==spec['initial']
    assert sum(end['phase'] == 'perform' for end in reader['finishes']) == 1
    assert sum(end['phase'] == 'complete' for end in reader['finishes']) == (0 if mp else 1)
    if case == 'pet-cancel':
        intervention = terminal['intervention']; snapshot(intervention['snapshot'], ids)
        assert intervention['kind'] == 'ISTimedActionQueue.clear' and body['startedAt'] <= intervention['at'] <= terminal['at']
        assert intervention['snapshot']['petting'] is True
    else: assert terminal['intervention'] is False
    if case == 'pet-invalid':
        gate = commands['gate']; assert gate['name'] == 'gate' and gate['type'] == 'ISReadABook' and gate['started'] is True and type(gate['starts']) is int and gate['starts'] == 1
        assert body['before']['distance'] >= 3
    return dict(effectsVerified=True, tailCompleted=True, authoritative=True, cleanupVerified=True,
                cancelled=case == 'pet-cancel', rejected=case == 'pet-invalid', originalTailPreserved=preserved)


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root); issues = []; outcomes = []
    try:
        text = (root/'client1-launch.log').read_text(errors='replace')
        authority = (root/'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        rows = events(text); results = [row for row in rows if row.get('event') == 'case']
        assert [r.get('event') for r in rows] == ['setup'] + ['case']*len(CASES) + ['complete'], 'missing/duplicate/reordered events'
        assert [r.get('id') for r in results] == CASES
        assert all(row.get(key) == value for row in rows for key,value in dict(suite='animal-terminal',kind=selection['kind'],mode=selection['mode'],actor='client1').items())
        assert rows[0]['queueEnabled'] is (selection['mode'] == 'toolkit') and rows[0]['nativeDurations'] is True
        assert all(rows[-1].get(key) == value for key,value in dict(cases=CASES,performed=3,failed=0,skipped=0).items())
        assert complete(selection, 'client1', text), 'missing exact raw completion'
        prepared, baselines, verified = (raw(authority, marker) for marker in ('PREPARED','BASELINE','VERIFIED'))
        assert len(prepared) == len(baselines) == len(verified) == 3, 'missing/duplicate authority raw snapshots'
        placements=raw(authority,'PLACEMENT')
        assert len(placements)==1 and placements[0]==dict(target=prepared[0]['placement'],arrived=True,teleports=1)
        assert all(row['placement']==prepared[0]['placement'] for row in prepared)
        if selection['kind']=='mp':
            assert raw(text,'CLIENT_PLACEMENT')==placements, 'local-client arrival target differs from authority replicated arrival'
        expected_xp=[dict(case=row['id'],event=entry) for row in results for entry in row['receipt']['final']['xpLedger']]
        assert raw(authority,'XP')==expected_xp, 'raw native Husbandry event ledger differs'
        assert raw(text, 'TERMINAL') == [row.get('terminal') for row in results], 'raw terminal evidence differs'
        enqueued = raw(text, 'ENQUEUED')
        assert [row.get('case') for row in enqueued] == CASES
        for queued, row in zip(enqueued, results):
            body = row['commands']['body']
            initial = {key: body[key] for key in ('name','type','duration','initialValid','producer')}
            initial.update(started=False,starts=0,nativeRef=False,finishes=[],terminal=False,ack=False)
            assert queued == dict(case=row['id'],body=initial,baseline=row['baseline'],tailDuration=row['commands']['tail']['duration']), 'raw enqueued native identities/durations differ'
        expected_begins=[]; expected_callbacks=[]; expected_acks=[]; expected_durations=[]
        for row in results:
            for action in row.get('commands', {}).values():
                if type(action) is not dict: continue
                if 'beginAt' in action:
                    timing=action['timing']
                    expected_begins.append(dict(case=row['id'],name=action['name'],at=action['beginAt'],snapshot=action['before'],
                        timing={key:timing[key] for key in ('constructor','beforeCreate','expectedAdjusted','sampleAt','source')}))
                    expected_durations.extend(dict(case=row['id'],name=action['name'],sample=sample) for sample in timing['samples'])
                expected_callbacks.extend(dict(case=row['id'],name=action['name'],callback=end) for end in action['finishes'])
                if action.get('wireTerminal'):
                    expected_acks.append(dict(case=row['id'],name=action['name'],**action['ack'],state=action['wireTerminal'],player=row['ids']['actor']))
        assert sorted(json.dumps(v,sort_keys=True) for v in raw(text,'BEGIN')) == sorted(json.dumps(v,sort_keys=True) for v in expected_begins), 'raw native begin evidence differs'
        assert sorted(json.dumps(v,sort_keys=True) for v in raw(text,'CALLBACK')) == sorted(json.dumps(v,sort_keys=True) for v in expected_callbacks), 'raw native callback evidence differs'
        assert sorted(json.dumps(v,sort_keys=True) for v in raw(text,'DURATION')) == sorted(json.dumps(v,sort_keys=True) for v in expected_durations), 'raw native duration observations differ'
        assert sorted(json.dumps(v,sort_keys=True) for v in raw(text,'ACK')) == sorted(json.dumps(v,sort_keys=True) for v in expected_acks), 'raw correlated Host receipt evidence differs'
        assert raw(text,'CANCEL') == [row['terminal']['intervention'] for row in results if row['id']=='pet-cancel']
    except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
        return dict(issues=['Invalid animal terminal evidence: '+(str(error) or 'schema differs')], outcomes=[])
    for i,row in enumerate(results):
        outcome = {}; problems = []
        try: outcome = check_case(row, selection, prepared[i], baselines[i], verified[i])
        except (AssertionError, KeyError, TypeError, ValueError) as error: problems.append(str(error) or 'native animal evidence differs')
        issues.extend(row.get('id','?')+': '+problem for problem in problems)
        outcomes.append(dict(actor='client1',case=row.get('id'),status='failed' if problems else 'passed',outcome=outcome))
    return dict(issues=issues,outcomes=outcomes)
