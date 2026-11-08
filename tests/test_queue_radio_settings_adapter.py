"""Radio settings logs must prove exact pending edits and native Host effects."""
import copy
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import report
from queue_checks.adapters import radio_settings as adapter


def placement_proof(target, mode='local'):
    actual = dict(target, square=dict(target), currentSquare=dict(target))
    if mode == 'local':
        actual.update(queued=0, timed=False, moving=False, hasPath=False, deferredX=0, deferredY=0)
    return dict(mode=mode, target=dict(target), actual=actual, teleports=1 if mode == 'local' else 0,
                stableMs=500, quietMs=500 if mode == 'local' else 0, elapsedMs=1500)


def preparation_proof(name, target, cancelled=False):
    result = dict(name=name, helper='walkAdj', target={key: target[key] for key in ('x', 'y', 'z')},
                  argumentCount=3, keepActions=True, owned=True, constructor=True, resolver=True,
                  sameOperation=True, started=not cancelled, completed=not cancelled, cancelled=cancelled)
    if not cancelled:
        point={key:target[key] for key in ('x','y','z')}
        actor=dict(x=point['x']+1.5,y=point['y']+.5,z=point['z'])
        result.update(children=0, succeeded=True,walks=[],resolution=dict(version=1,noMovement=True,actor=actor,
            square=dict(x=point['x']+1,y=point['y'],z=point['z']),target=dict(point),correctedTarget=dict(point),
            collideW=False,collideN=False,diffX=1,diffY=0,reachEvaluated=True,canReach=True))
    return result


class RadioSettingsAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def selection(self, case, kind='sp', mode='toolkit'):
        return dict(suite='radio-settings', cases=[case], kind=kind, mode=mode,
                    clients=1, languages=['EN'], mods=list(adapter.MODS),
                    options={'mp_host': True} if kind == 'mp' else {})

    def evidence(self, case, kind='sp', mode='toolkit'):
        ids = dict(case=case, mode=mode, a=dict(x=11, y=20, z=0, index=2),
                   b=dict(x=9, y=20, z=0, index=1))

        ids['origin'] = dict(x=10, y=20, z=0)
        ids['placementProof'] = placement_proof(ids['origin'], 'replica' if kind == 'mp' else 'local')

        def snapshot(initial=False, server=False):
            devices = {}
            for name in ('a', 'b'):
                volume = (.5 if initial else .25 if name == 'b' else 0 if case == 'barrier'
                          else .25 if mode == 'toolkit' else .75)
                channel = 90000 if initial else 96000 if name == 'b' else 95000
                muted = (not initial and not server and name == 'a' and case != 'barrier'
                         and (case != 'cancel' or mode == 'native'))
                devices[name] = dict(ids[name], volume=volume, channel=channel,
                                     micMuted=muted, on=True, powered=True)
            return dict(case=case, devices=devices)

        specs = [('anchor', 'SetVolume', 'b', .25), ('firstVolume', 'SetVolume', 'a', .25)]
        if case == 'barrier':
            specs += [('channel', 'SetChannel', 'a', 95000), ('powerOff', 'ToggleOnOff', 'a', None),
                      ('powerOn', 'ToggleOnOff', 'a', None), ('legacyMute', 'MuteVolume', 'a', True)]
        else:
            specs += [('channel', 'SetChannel', 'a', 95000), ('lastVolume', 'SetVolume', 'a', .75),
                      ('mic', 'MuteMicrophone', 'a', True)]
        specs += [('tail', 'SetChannel', 'b', 96000)]
        cancelled = ['lastVolume', 'mic'] if case == 'cancel' and mode == 'toolkit' else []
        initial = [name for name, _, _, _ in specs]
        expected = (['anchor', 'lastVolume', 'firstVolume', 'mic', 'channel', 'tail']
                    if case == 'reorder' and mode == 'toolkit'
                    else [name for name in initial if name not in cancelled])
        commands = []
        for name, action, target, value in specs:
            removed = name in cancelled
            command = dict(name=name, mode=action, target=target, value=value, duration=30,
                           producer='native RWM callback', started=not removed,
                           progress=not removed, cancelled=removed)
            if not removed:
                command.update(effectiveDuration=30, nativeDurationExpected=30,
                               startedAt=1000 + expected.index(name) * 100)
            if mode == 'toolkit':
                command['preparation'] = preparation_proof(name, ids[target], removed)
            commands.append(command)
        before = snapshot(initial=True)
        client = snapshot()
        authority = snapshot(server=kind == 'mp')
        row = dict(suite='radio-settings', event='case', id=case, kind=kind, mode=mode,
                   actor='client1', status='passed', ids=copy.deepcopy(ids), clientPlacement=placement_proof(ids['origin']), commands=commands,
                   initialQueue=initial, editedQueue=list(expected), order=list(expected),
                   edit=dict(reordered=case == 'reorder' and mode == 'toolkit', cancelled=cancelled,
                             denied=case == 'barrier' and mode == 'toolkit', reason='move_dependent',
                             untouchedBefore=True, nativeDurations=True, before=before),
                   client=client, server=copy.deepcopy(authority), queueIdle=True, settleMilliseconds=2000)
        def physical(names):
            return [part for name in names for part in ([name + ':approach', name]
                    if mode == 'toolkit' and name != 'anchor' else [name])]
        row.update(initialPhysicalQueue=physical(initial), editedPhysicalQueue=physical(expected))
        return row, ids, authority

    def verify(self, selection, evidence, *, prepared=True, verified=True, malformed_raw=None,
               completion='[RADIO_SETTINGS] COMPLETE', placements=None):
        row, ids, receipt = evidence
        # Use timestamped records just as the live launcher does.
        stamp = 'LOG : General > '
        placement_rows = [{'case': row['id'], 'proof': row.get('clientPlacement')}] if placements is None else placements
        client = ''.join(stamp + '[RADIO_SETTINGS] CLIENT_PLACEMENT ' + json.dumps(value) + '\n' for value in placement_rows)
        client += stamp + '[QUEUE_CHECK] ' + json.dumps(row) + '\n' + completion + '\n'
        client += ''.join('[QUEUE_TEST] ' + marker + '\n' for marker in
                          ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE',
                           'NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'))
        raw = []
        if prepared:
            raw.append('[RADIO_SETTINGS] PREPARED ' + json.dumps(ids))
        if verified:
            raw.append('[RADIO_SETTINGS] VERIFIED ' + json.dumps(receipt))
        if malformed_raw is not None:
            marker, value = malformed_raw
            raw = [line for line in raw if not line.startswith('[RADIO_SETTINGS] ' + marker)]
            raw.append('[RADIO_SETTINGS] ' + marker + ' ' + value)
        authority = '\n'.join(stamp + line for line in raw) + '\n'
        if selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text(authority)
        else:
            client += authority
        (self.root / 'client1-launch.log').write_text(client)
        return adapter.verify(self.root, selection, {})

    def matrix(self):
        return itertools.product(adapter.CASES, ('sp', 'mp'), ('native', 'toolkit'))

    def test_native_expansion_is_conditional_and_requires_exact_child_completion(self):
        for kind in ('sp','mp'):
            selection=self.selection('cancel',kind)
            evidence=self.evidence('cancel',kind)
            proof=next(c for c in evidence[0]['commands'] if c['name']=='channel')['preparation']
            proof['resolution'].update(noMovement=False,canReach=False)
            destination=copy.deepcopy(proof['resolution']['square'])
            start=copy.deepcopy(proof['resolution']['actor'])
            proof.update(children=1,walks=[dict(type='ISWalkToTimedAction',duration=-1,sameOperation=True,
                nativeCallbacks=True,starts=1,started=True,progress=True,completed=True,succeeded=True,
                atDestination=True,destination=destination,startPosition=start,
                arrival=dict(x=destination['x']+.5,y=destination['y']+.5,z=destination['z']),
                startedAt=1000,progressAt=1010,completedAt=1020)])
            self.assertEqual(self.verify(selection,evidence)['issues'],[])
            mutations={
                'no child when native predicate false':lambda p:p.update(children=0,walks=[]),
                'invented native predicate':lambda p:p['resolution'].update(noMovement=True),
                'wrong correction':lambda p:p['resolution']['correctedTarget'].update(x=99),
                'wrong native distance':lambda p:p['resolution'].update(diffX=0),
                'foreign child type':lambda p:p['walks'][0].update(type='FixtureWalk'),
                'foreign callback':lambda p:p['walks'][0].update(nativeCallbacks=False),
                'foreign operation':lambda p:p['walks'][0].update(sameOperation=False),
                'duration changed':lambda p:p['walks'][0].update(duration=1),
                'unobserved start':lambda p:p['walks'][0].update(started=False),
                'no walking progress':lambda p:p['walks'][0].update(progress=False),
                'failed walking':lambda p:p['walks'][0].update(succeeded=False),
                'missing native completion':lambda p:p['walks'][0].update(completed=False),
                'wrong arrival':lambda p:p['walks'][0]['arrival'].update(x=99),
                'stale completion ordering':lambda p:p['walks'][0].update(completedAt=999),
                'completion after setter observation':lambda p:p['walks'][0].update(completedAt=1500),
                'no arrival proof':lambda p:p['walks'][0].update(atDestination=False),
                'replayed child':lambda p:p['walks'][0].update(starts=2),
                'duplicate child':lambda p:p['walks'].append(copy.deepcopy(p['walks'][0])),
            }
            for label,mutate in mutations.items():
                with self.subTest(kind=kind,mutation=label):
                    changed=copy.deepcopy(evidence)
                    candidate=next(c for c in changed[0]['commands'] if c['name']=='channel')['preparation']
                    mutate(candidate);self.assertTrue(self.verify(selection,changed)['issues'])
            # Native wall correction order is independently recomputed by the
            # verifier; a west correction wins when both flags are present.
            resolution=proof['resolution'];resolution['actor']['x']=proof['target']['x']-.5
            resolution.update(collideW=True,collideN=True,diffX=2,diffY=0,reachEvaluated=False,canReach=False)
            resolution['correctedTarget']['x']+=1
            self.assertEqual(self.verify(selection,evidence)['issues'],[])

    def test_placement_proofs_require_independent_roles_and_settled_squares(self):
        for kind in ('sp', 'mp'):
            selection = self.selection('reorder', kind)
            for location in ('client', 'authority'):
                for mutation in ('missing', 'wrong-role', 'teleports', 'unsettled', 'stale-square', 'target', 'motion'):
                    if location == 'authority' and kind == 'mp' and mutation == 'motion':
                        continue
                    with self.subTest(kind=kind, location=location, mutation=mutation):
                        evidence = self.evidence('reorder', kind)
                        row, ids = evidence[:2]
                        owner = row if location == 'client' else ids
                        key = 'clientPlacement' if location == 'client' else 'placementProof'
                        proof = owner[key]
                        if mutation == 'missing': owner.pop(key)
                        elif mutation == 'wrong-role': proof['mode'] = 'replica' if proof['mode'] == 'local' else 'local'
                        elif mutation == 'teleports': proof['teleports'] += 1
                        elif mutation == 'unsettled': proof['stableMs'] = 499
                        elif mutation == 'stale-square': proof['actual']['currentSquare']['x'] += 1
                        elif mutation == 'target': proof['target']['x'] += 1
                        else: proof['actual']['hasPath'] = True
                        if location == 'authority': row['ids'] = copy.deepcopy(ids)
                        self.assertTrue(self.verify(selection, evidence)['issues'])
        evidence = self.evidence('reorder', 'mp')
        row, ids = evidence[:2]
        # Ordinary replicated coordinates/timing can differ from the local receipt.
        ids['placementProof']['actual']['x'] += .25
        ids['placementProof']['stableMs'] = 600
        row['ids'] = copy.deepcopy(ids)
        self.assertEqual(self.verify(self.selection('reorder', 'mp'), evidence)['issues'], [])

    def test_raw_client_placement_must_be_unique_matching_and_case_correlated(self):
        for kind in ('sp', 'mp'):
            evidence = self.evidence('reorder', kind)
            value = dict(case='reorder', proof=evidence[0]['clientPlacement'])
            for placements in ([], [value, value], [dict(value, case='cancel')],
                               [dict(value, proof=placement_proof(dict(x=50, y=20, z=0)))]):
                with self.subTest(kind=kind, placements=placements):
                    self.assertTrue(self.verify(self.selection('reorder', kind), evidence, placements=placements)['issues'])

    def test_approach_proof_and_physical_queue_fail_closed(self):
        for kind in ('sp', 'mp'):
            for location, value in (
                ('helper', 'walkAdjWall'), ('argumentCount', 4), ('keepActions', False), ('owned', False),
                ('constructor', False), ('resolver', False), ('sameOperation', False), ('started', False),
                ('completed', False), ('succeeded', False), ('children', 1), ('children', False),
                ('cancelled', True), ('name', 'other')):
                with self.subTest(kind=kind, field=location, value=value):
                    evidence = self.evidence('reorder', kind)
                    row = evidence[0]
                    command = next(c for c in row['commands'] if c['name'] == 'firstVolume')
                    command['preparation'][location] = value
                    self.assertTrue(self.verify(self.selection('reorder', kind), evidence)['issues'])
            for field in ('initialPhysicalQueue', 'editedPhysicalQueue'):
                evidence = self.evidence('reorder', kind)
                evidence[0][field] = list(evidence[0]['initialQueue'])
                self.assertTrue(self.verify(self.selection('reorder', kind), evidence)['issues'])
            for field in ('preparation',):
                evidence = self.evidence('reorder', kind)
                next(c for c in evidence[0]['commands'] if c['name'] == 'firstVolume').pop(field)
                self.assertTrue(self.verify(self.selection('reorder', kind), evidence)['issues'])
            evidence = self.evidence('reorder', kind)
            next(c for c in evidence[0]['commands'] if c['name'] == 'firstVolume')['preparation']['target']['x'] += 1
            self.assertTrue(self.verify(self.selection('reorder', kind), evidence)['issues'])
            evidence = self.evidence('reorder', kind, 'native')
            next(c for c in evidence[0]['commands'] if c['name'] == 'firstVolume')['preparation'] = preparation_proof('firstVolume', evidence[1]['a'])
            self.assertTrue(self.verify(self.selection('reorder', kind, 'native'), evidence)['issues'])

    def test_cancelled_dispatcher_cannot_execute_or_remain_in_physical_queue(self):
        for kind in ('sp', 'mp'):
            for mutation in ('started', 'completed', 'retained'):
                evidence = self.evidence('cancel', kind)
                row = evidence[0]
                preparation = next(c for c in row['commands'] if c['name'] == 'lastVolume')['preparation']
                if mutation == 'retained': row['editedPhysicalQueue'].insert(1, 'lastVolume:approach')
                else: preparation[mutation] = True
                self.assertTrue(self.verify(self.selection('cancel', kind), evidence)['issues'])

    def test_native_nil_toggle_argument_can_be_omitted_but_setter_values_remain_required(self):
        for kind in ('sp', 'mp'):
            selection = self.selection('barrier', kind, 'native')
            evidence = self.evidence('barrier', kind, 'native')
            for command in evidence[0]['commands']:
                if command['mode'] == 'ToggleOnOff':
                    command.pop('value')
            self.assertEqual(self.verify(selection, evidence)['issues'], [])
            for name, value in (('powerOff', False), ('powerOn', 0), ('firstVolume', None), ('channel', None)):
                with self.subTest(kind=kind, name=name):
                    changed = copy.deepcopy(evidence)
                    command = next(c for c in changed[0]['commands'] if c['name'] == name)
                    if value is None:
                        command.pop('value')
                    else:
                        command['value'] = value
                    self.assertTrue(self.verify(selection, changed)['issues'])

    def test_lua_preparation_proves_exact_intent_and_observes_synchronous_completion(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/radio-settings/client/ZZRadioSettings.lua').read_text()
        helper = 'local preparations={}' + source.split('local preparations={}', 1)[1].split('local function queueNames', 1)[0]
        prefix = """
            local native=false;local watchPreparations
            local square={getX=function()return 10 end,getY=function()return 20 end,getZ=function()return 0 end,
                has=function()return false end}
            local reach=true;local playerX=11.5
            local origin={getX=function()return 11 end,getY=function()return 20 end,getZ=function()return 0 end,
                canReachTo=function()return reach end}
            local player={getX=function()return playerX end,getY=function()return 20.5 end,getZ=function()return 0 end,
                getSquare=function()return origin end,getCurrentSquare=function()return origin end,
                isMoving=function()return false end,isPlayerMoving=function()return false end,
                isPathfindRunning=function()return false end,getPath2=function()end}
            IsoFlagType={collideW='west',collideN='north'}
            getCell=function()return {getGridSquare=function(_,x,y,z)return x==10 and square or origin end}end
            ISWalkToTimedAction={Type='ISWalkToTimedAction'};ISWalkToTimedAction.__index=ISWalkToTimedAction
            for _,name in ipairs({'new','start','update','stop','perform','isValid'})do ISWalkToTimedAction[name]=function()end end
            ISWalkToTimedAction.isStarted=function(self)return self.started==true end
            instanceof=function(value,name)return name=='IsoGridSquare'and(value==origin or value==square)end
            BehaviorResult={Succeeded='succeeded'}
            getTimestampMs=function()return 1000 end
            getFilenameOfClosure=function()return 'media/lua/client/TimedActions/WalkToTimedAction.lua'end
            local device={getSquare=function()return square end}
            local q={queue={},indexOf=function(self,a)for i,v in ipairs(self.queue)do if v==a then return i end end;return -1 end}
            local function queue()return q end
            getPlayer=function()return player end;luautils={}
            local observers
            local T={ActionQueueApproach={isAction=function(a)return not a.foreign end,capture=function(a)return not a.unsealed and not a.action end},
                ActionQueueOperations={commandConstructionTrusted=function()return true end},
                ActionQueueLifecycle={registerObserver=function(_,value)observers=value;return true end}}
            local function action()
                return {character=player,toolkitQueueOperation={},
                    toolkitQueueCommand={snapshot={binding={owner=luautils,name='walkAdj'},args={n=3,player,square,true}}}}
            end
        """
        suffix = """
            local beginDiagnostics={}
            raw=function(marker,value)assert(marker=='PREPARATION_BEGIN');beginDiagnostics[#beginDiagnostics+1]=value end
            case=function()return 'case'end
            watchPreparations()
            local first=action()
            local proof=capturePreparation(first,'anchor',device)
            -- Native add may start/resolve the anchor before its setter exists.
            q.current=first;q.queue={first};observers.started(first);first.action={};first._numAddedActions=nil
            assert(observers.begin(first,'perform')==nil);observers.finish(first,'perform',true)
            q.current=nil;q.queue={}
            assert(pairPreparation(first,{toolkitQueueOperation=first.toolkitQueueOperation})==proof)
            verifyPreparations();assert(proof.started and proof.completed and proof.children==0)
            for _,mutate in ipairs({
                function(a)a.foreign=true end,function(a)a.unsealed=true end,function(a)a.character={}end,
                function(a)a.toolkitQueueCommand.snapshot.binding.owner={}end,
                function(a)a.toolkitQueueCommand.snapshot.binding.name='walkAdjWall'end,
                function(a)a.toolkitQueueCommand.snapshot.args.n=4 end,
                function(a)a.toolkitQueueCommand.snapshot.args[1]={}end,
                function(a)a.toolkitQueueCommand.snapshot.args[2]={}end,
                function(a)a.toolkitQueueCommand.snapshot.args[3]=false end,
            })do local bad=action();mutate(bad);assert(not pcall(capturePreparation,bad,'bad',device))end
            local pending=action();capturePreparation(pending,'cancelled',device)
            assert(not pcall(pairPreparation,pending,{toolkitQueueOperation={}}))
            pairPreparation(pending,{toolkitQueueOperation=pending.toolkitQueueOperation})
            q.queue={pending};assert(not pcall(cancelPreparation,'cancelled'))
            q.queue={};cancelPreparation('cancelled');verifyPreparations()
            local walked=action();capturePreparation(walked,'walked',device)
            local setter={toolkitQueueOperation=walked.toolkitQueueOperation}
            pairPreparation(walked,setter)
            local child={Type='ISWalkToTimedAction',toolkitQueueOperation=walked.toolkitQueueOperation}
            q.queue={walked,child,setter};q.current=walked;observers.started(walked);walked.action={};walked._numAddedActions=nil
            assert(not pcall(observers.begin,walked,'perform'));observers.finish(walked,'perform',true)
            local diagnostic=beginDiagnostics[#beginDiagnostics]
            assert(diagnostic.name=='walked'and diagnostic.queue[2].type=='ISWalkToTimedAction')
            assert(diagnostic.queue[2].selectedOperation and diagnostic.queue[1].token==diagnostic.queue[2].token)
            assert(diagnostic.setter==diagnostic.queue[3].action and diagnostic.setter~=diagnostic.queue[2].action)
            assert(q.queue[1]==walked and q.queue[2]==child and q.queue[3]==setter,'diagnostics mutated the native queue')
            q.current=nil;assert(not pcall(verifyPreparations))
            -- A real native-class child is required when the copied native
            -- near predicate is false; no constructor/callback is replayed.
            preparations={};walking={};reach=false
            local routed=action();capturePreparation(routed,'routed',device)
            local routedSetter={toolkitQueueOperation=routed.toolkitQueueOperation}
            pairPreparation(routed,routedSetter)
            local nativeChild=setmetatable({character=player,toolkitQueueOperation=routed.toolkitQueueOperation,
                maxTime=-1,stopOnWalk=false,stopOnRun=false,allowedWhileDraggingCorpses=true,location=origin},ISWalkToTimedAction)
            q.current=routed;q.queue={routed,nativeChild,routedSetter};observers.started(routed)
            observers.begin(routed,'perform');observers.finish(routed,'perform',true)
            local proof=preparations[routed].proof
            assert(not proof.resolution.noMovement and proof.children==1 and #proof.walks==1)
            q.current=nativeChild;q.queue={nativeChild,routedSetter};observers.started(nativeChild);nativeChild.started=true
            playerX=11.55;observeWalking();nativeChild.result=BehaviorResult.Succeeded
            observers.finish(nativeChild,'perform',true)
            q.current=nil;q.queue={};verifyPreparations()
            assert(proof.walks[1].progress and proof.walks[1].atDestination and proof.walks[1].starts==1)
            assert(not pcall(observers.started,nativeChild),'a native child cannot replay')
            for _,kind in ipairs({'foreign-callback','foreign-token','foreign-class','wrong-duration','wrong-flags',
                'foreign-selector','wrong-setter-token','extra-after-setter','missing-child','unexpected-near-child'})do
                preparations={};walking={};reach=kind=='unexpected-near-child'
                local prep=action();capturePreparation(prep,kind,device)
                local body={toolkitQueueOperation=prep.toolkitQueueOperation};pairPreparation(prep,body)
                local value=setmetatable({character=player,toolkitQueueOperation=prep.toolkitQueueOperation,
                    maxTime=-1,stopOnWalk=false,stopOnRun=false,allowedWhileDraggingCorpses=true,location=origin},ISWalkToTimedAction)
                local forbiddenCalls=0
                if kind=='foreign-callback'then value.isValid=function()forbiddenCalls=forbiddenCalls+1;error('foreign child callback')end
                elseif kind=='foreign-token'then value.toolkitQueueOperation={}
                elseif kind=='foreign-class'then setmetatable(value,{__index=ISWalkToTimedAction})
                elseif kind=='wrong-duration'then value.maxTime=1
                elseif kind=='wrong-flags'then value.stopOnRun=true
                elseif kind=='foreign-selector'then value.additionalTest=function()forbiddenCalls=forbiddenCalls+1;error('foreign selector')end
                elseif kind=='wrong-setter-token'then body.toolkitQueueOperation={}end
                q.current=prep;q.queue={prep,value,body};observers.started(prep)
                if kind=='missing-child'then q.queue={prep,body}
                elseif kind=='extra-after-setter'then q.queue[4]={Type='ISReadABook',toolkitQueueOperation=prep.toolkitQueueOperation}end
                assert(not pcall(observers.begin,prep,'perform'),'malformed native child accepted: '..kind)
                assert(forbiddenCalls==0,'observer executed a foreign child callback')
            end
            for _,phase in ipairs({'started','progress','finish','verify'})do
             for _,owner in ipairs({'child','preparation','setter'})do
                preparations={};walking={};reach=false;playerX=11.5
                local prep=action();capturePreparation(prep,'late-token',device)
                local body={toolkitQueueOperation=prep.toolkitQueueOperation};pairPreparation(prep,body)
                local value=setmetatable({character=player,toolkitQueueOperation=prep.toolkitQueueOperation,
                    maxTime=-1,stopOnWalk=false,stopOnRun=false,allowedWhileDraggingCorpses=true,location=origin},ISWalkToTimedAction)
                q.current=prep;q.queue={prep,value,body};observers.started(prep)
                observers.begin(prep,'perform');observers.finish(prep,'perform',true)
                local target=owner=='child'and value or owner=='preparation'and prep or body
                q.current=value;q.queue={value,body}
                if phase~='started'then observers.started(value);value.started=true end
                if phase=='finish'or phase=='verify'then playerX=11.55;observeWalking();value.result=BehaviorResult.Succeeded end
                if phase=='verify'then observers.finish(value,'perform',true);q.current=nil;q.queue={}end
                target.toolkitQueueOperation={}
                local accepted
                if phase=='started'then accepted=pcall(observers.started,value)
                elseif phase=='progress'then accepted=pcall(observeWalking)
                elseif phase=='finish'then accepted=pcall(observers.finish,value,'perform',true)
                else accepted=pcall(verifyPreparations)end
                assert(not accepted,'post-collection token mutation accepted: '..owner..'/'..phase)
                assert(not preparations[prep].proof.walks[1].sameOperation,'stale sameOperation receipt survived token replacement')
             end
            end
        """
        lua = LuaRuntime()
        lua.execute(prefix + helper + suffix)

    def test_lua_prepare_sends_only_after_one_local_settled_placement(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/radio-settings/client/ZZRadioSettings.lua').read_text()
        request = 'local placement,placementState,clientPlacement' + source.split('local placement,placementState,clientPlacement', 1)[1].split('Events.OnServerCommand.Add', 1)[0]
        prepare = source.split("if phase=='prepare'then", 1)[1].split("elseif phase=='prepared'and ids then", 1)[0]
        lua = LuaRuntime()
        lua.execute("""
            sent=0;begins=0;chooses=0;polls=0;ready=false;fresh=true;raws=0
            local target={x=10,y=20,z=0};local player={};local receipt={mode='local',target=target}
            P={choose=function(p)assert(p==player);chooses=chooses+1;return target end,
                begin=function(p,t)assert(p==player and t==target);begins=begins+1;return {}end,
                poll=function()polls=polls+1;return ready and receipt or nil end,
                at=function(p,t)assert(p==player and t==target);return fresh end}
            getPlayer=function()return player end;isClient=function()return true end
            sendClientCommand=function(module,command,args)
                assert(command=='Prepare' and args.case=='case' and args.placement==target and args.clientPlacement==receipt)
                sent=sent+1
            end
            raw=function(marker,args)assert(marker=='CLIENT_PLACEMENT'and args.case=='case'and args.proof==receipt);raws=raws+1 end
            empty=function()return true end;case=function()return 'case'end
            local phase='prepare'
        """ + request + "\nstep=function()local player=getPlayer();if phase=='prepare'then " + prepare + " end end\nrequestForTest=request")
        lua.execute('step();assert(sent==0 and begins==1 and chooses==1 and polls==1);step();assert(sent==0 and begins==1 and chooses==1 and polls==2)')
        lua.execute('ready=true;step();assert(sent==1 and begins==1 and chooses==1 and polls==3 and raws==1);step();assert(sent==1)')
        lua.execute("fresh=false;assert(not pcall(requestForTest,'Prepare'));assert(not pcall(requestForTest,'Unknown'));assert(sent==1)")

    def test_lua_authority_defers_whole_prepare_and_rechecks_position(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/radio-settings/server/ZZRadioSettingsServer.lua').read_text()
        for left_tile in (False, True):
            lua = LuaRuntime()
            lua.execute("""
                callbacks={};calls=0;settled=false;fresh=true
                isServer=function()return true end
                getTimestampMs=function()return 1000 end
                print=function()end
                Events={OnClientCommand={Add=function(f)callbacks.command=f end},OnTick={Add=function(f)callbacks.tick=f end}}
                sendServerCommand=function(player,module,command,args)lastCommand=command end
                player={getUsername=function()return 'client1'end}
                target={x=10,y=20,z=0}
                P={target=function(t)return t end,observe=function(p,t)assert(p==player and t==target);return {}end,
                   poll=function()return settled and {mode='replica'}or nil end,at=function()return fresh end}
                F={prepare=function(...)calls=calls+1;return {ids={case='reorder'}}end}
                package.preload.QueueEnergyPlacement=function()return P end
                package.preload.QueueRadioSettings=function()return F end
                package.preload.QueueHealthEvents=function()return {encode=function()return '{}'end}end
                package.preload.QueueTestSelection=function()return {cases={'reorder'},mode='toolkit'}end
            """)
            lua.execute(source)
            lua.execute("callbacks.command('RadioSettingsTest','Prepare',player,{case='reorder',placement=target,clientPlacement={mode='local'}});assert(calls==0);callbacks.tick();assert(calls==0)")
            lua.globals().fresh = not left_tile
            lua.execute('settled=true;callbacks.tick()')
            self.assertEqual(lua.globals().calls, 0 if left_tile else 1)
            self.assertEqual(lua.globals().lastCommand, 'Failed' if left_tile else 'Prepared')
        lua = LuaRuntime()
        lua.execute("isServer=function()return true end;package.preload.QueueEnergyPlacement=function()return {target=function(t)return t end,at=function()return false end}end")
        fixture = lua.execute((ROOT / 'tests/native_queue/radio-settings/shared/QueueRadioSettings.lua').read_text())
        # No getCell/item constructors exist: precondition must fail before scene or inventory mutations.
        with self.assertRaisesRegex(Exception, 'left settled placement'):
            fixture.prepare(lua.table(), 'reorder', 'toolkit', None, lua.table(x=10, y=20, z=0))

    def test_valid_evidence_for_all_cases_modes_and_sp_host(self):
        for case, kind, mode in self.matrix():
            with self.subTest(case=case, kind=kind, mode=mode):
                selection = self.selection(case, kind, mode)
                adapter.validate(selection)
                result = self.verify(selection, self.evidence(case, kind, mode))
                self.assertEqual(result['issues'], [])
                self.assertEqual([row['status'] for row in result['outcomes']], ['passed'])

    def test_verified_outcomes_nest_scenario_flags_for_report_consumers(self):
        for case, kind, mode in self.matrix():
            with self.subTest(case=case, kind=kind, mode=mode):
                result = self.verify(self.selection(case, kind, mode), self.evidence(case, kind, mode))
                self.assertEqual(result['issues'], [])
                self.assertEqual(result['outcomes'][0].get('outcome'), {
                    'effectsVerified': True, 'pendingRequestsVerified': True,
                    'pendingEditsVerified': mode == 'toolkit', 'serverAuthorityVerified': True,
                })

    def test_verified_radio_evidence_maps_to_scenarios_and_native_edit_is_inapplicable(self):
        catalog = {'suites': adapter.definitions()}
        mapped = {'reorder': 'move-independent', 'cancel': 'cancel-waiting', 'barrier': 'move-dependent'}
        for case, kind, mode in self.matrix():
            with self.subTest(case=case, kind=kind, mode=mode):
                selection = self.selection(case, kind, mode)
                self.assertEqual(self.verify(selection, self.evidence(case, kind, mode))['issues'], [])
                functional, coverage = report.functional(self.root, selection, catalog)
                self.assertEqual(functional['issues'], [])
                processes = {'client1': {'pid': 123, 'exit_code': 0}}
                execution = {'status': 'completed', 'processes': processes}
                if kind == 'mp':
                    processes['server'] = {'pid': 124, 'parent_role': 'client1',
                                           'cache': str(self.root / 'client1')}
                    execution['host_cleanup'] = {'remaining_pids': []}
                recorded = dict(run=str(self.root), status='passed', selection=selection,
                                functional=functional, coverage=coverage, execution=execution,
                                provenance={'verified': True})
                scenario = next(row for row in report.matrix(catalog, [recorded])['scenarios']
                                if row['suite'] == 'radio-settings' and row['action'] == 'world-radio-settings'
                                and row['scenario'] == mapped[case] and row['kind'] == kind and row['mode'] == mode)
                self.assertEqual(scenario['status'], 'not-applicable' if mode == 'native' else 'passed')

    def test_exact_device_identity_is_required_even_for_matching_receipts(self):
        for case, kind, mode in self.matrix():
            for field in ('x', 'y', 'z', 'index'):
                with self.subTest(case=case, kind=kind, mode=mode, field=field):
                    evidence = self.evidence(case, kind, mode)
                    row, _, receipt = evidence
                    # Matching client/server claims cannot replace the prepared object.
                    for changed in (row['client'], row['server'], receipt):
                        changed['devices']['a'][field] += 1
                    self.assertTrue(self.verify(self.selection(case, kind, mode), evidence)['issues'])

    def test_dispatch_edit_and_observed_order_are_independently_required(self):
        for case, kind, mode in self.matrix():
            for field in ('initialQueue', 'editedQueue', 'order'):
                with self.subTest(case=case, kind=kind, mode=mode, field=field):
                    evidence = self.evidence(case, kind, mode)
                    evidence[0][field][-2:] = reversed(evidence[0][field][-2:])
                    self.assertTrue(self.verify(self.selection(case, kind, mode), evidence)['issues'])

    def test_cancelled_native_actions_cannot_have_started_or_made_progress(self):
        for kind, name, field in itertools.product(('sp', 'mp'), ('lastVolume', 'mic'), ('started', 'progress')):
            with self.subTest(kind=kind, name=name, field=field):
                evidence = self.evidence('cancel', kind)
                command = next(row for row in evidence[0]['commands'] if row['name'] == name)
                command[field] = True
                self.assertTrue(self.verify(self.selection('cancel', kind), evidence)['issues'])

    def test_native_adjustment_is_accepted_but_retiming_is_rejected(self):
        for case, kind, mode in self.matrix():
            for effective, accepted in ((30.02, True), (31.02, False)):
                with self.subTest(case=case, kind=kind, mode=mode, effective=effective):
                    evidence = self.evidence(case, kind, mode)
                    for command in evidence[0]['commands']:
                        if not command['cancelled']:
                            command['nativeDurationExpected'] = 30.02
                            command['effectiveDuration'] = effective
                    result = self.verify(self.selection(case, kind, mode), evidence)
                    if accepted:
                        self.assertEqual(result['issues'], [])
                    else:
                        self.assertTrue(result['issues'])

    def test_host_cannot_fabricate_native_microphone_replication(self):
        for case, mode in itertools.product(adapter.CASES, ('native', 'toolkit')):
            with self.subTest(case=case, mode=mode):
                evidence = self.evidence(case, 'mp', mode)
                evidence[0]['server']['devices']['a']['micMuted'] = True
                evidence[2]['devices']['a']['micMuted'] = True
                self.assertTrue(self.verify(self.selection(case, 'mp', mode), evidence)['issues'])

    def test_receipt_and_authoritative_markers_cannot_be_omitted(self):
        for case, kind, mode in self.matrix():
            selection = self.selection(case, kind, mode)
            for field in ('client', 'server'):
                with self.subTest(case=case, kind=kind, mode=mode, field=field):
                    evidence = self.evidence(case, kind, mode)
                    del evidence[0][field]
                    self.assertTrue(self.verify(selection, evidence)['issues'])
            for marker in ('prepared', 'verified'):
                with self.subTest(case=case, kind=kind, mode=mode, marker=marker):
                    self.assertTrue(self.verify(selection, self.evidence(case, kind, mode), **{marker: False})['issues'])

    def test_malformed_receipts_are_rejected_without_crashing_verifier(self):
        malformed = (None, [], 'receipt', {}, {'case': 'reorder', 'devices': None},
                     {'case': 'reorder', 'devices': 'ab'}, {'case': 'reorder', 'devices': ['a', 'b']},
                     {'case': 'reorder', 'devices': {'a': None, 'b': None}})
        for kind, field, value in itertools.product(('sp', 'mp'), ('client', 'server'), malformed):
            with self.subTest(kind=kind, field=field, value=value):
                evidence = self.evidence('reorder', kind)
                evidence[0][field] = copy.deepcopy(value)
                if field == 'server':
                    evidence = (evidence[0], evidence[1], copy.deepcopy(value))
                self.assertTrue(self.verify(self.selection('reorder', kind), evidence)['issues'])

    def test_malformed_authority_json_is_rejected_without_crashing_verifier(self):
        for kind, marker, value in itertools.product(('sp', 'mp'), ('PREPARED', 'VERIFIED'),
                                                     ('null', '[]', '"receipt"', '{invalid')):
            with self.subTest(kind=kind, marker=marker, value=value):
                result = self.verify(self.selection('reorder', kind), self.evidence('reorder', kind),
                                     malformed_raw=(marker, value))
                self.assertTrue(result['issues'])

    def test_missing_or_duplicate_completion_does_not_pass(self):
        for marker in ('', '[RADIO_SETTINGS] COMPLETE_PENDING',
                       '[RADIO_SETTINGS] COMPLETE\n[RADIO_SETTINGS] COMPLETE'):
            with self.subTest(marker=marker):
                self.assertTrue(self.verify(self.selection('reorder'), self.evidence('reorder'),
                                            completion=marker)['issues'])


if __name__ == '__main__':
    unittest.main()
