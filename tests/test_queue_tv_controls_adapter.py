"""Exact TV media/Host evidence gate, with causal negative mutations."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import tv_controls as a


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
        result.update(children=0, succeeded=True)
    return result


class TVControlsTests(unittest.TestCase):
    def selection(self, kind='mp', mode='toolkit'):
        return dict(suite='tv-controls', cases=list(a.CASES), kind=kind, mode=mode,
                    clients=1, languages=['EN'], mods=list(a.MODS), options={'mp_host': True} if kind == 'mp' else {})

    def evidence(self, case, kind='mp', mode='toolkit'):
        offset = 0 if case == 'eject-idle' else 10
        ids = dict(case=case, mode=mode, tv=dict(x=10, y=20, z=0, index=1), origin=dict(x=11, y=20, z=0),
                   front=dict(id=101+offset, type='Base.BookCarpentry1', pages=220, initial=218),
                   tail=dict(id=102+offset, type='Base.BookCooking1', pages=220, initial=218),
                   tape=dict(id=103+offset, type='Base.VHS_Retail', index=7, mediaType=1))
        ids['placementProof'] = placement_proof(ids['origin'], 'replica' if kind == 'mp' else 'local')
        output = 104+offset
        def snapshot(phase):
            final = phase == 'final'; baseline = phase == 'baseline'
            books = {name: dict(id=ids[name]['id'], type=ids[name]['type'], count=1, root=True, total=220,
                                pages=220 if final else 218, characterPages=220 if final else 218) for name in ('front', 'tail')}
            inventory=sorted([ids['front']['id'], ids['tail']['id']] +
                        ([ids['tape']['id']] if phase == 'input' else [output] if final else []))
            return dict(case=case, tv=ids['tv'], carriedIds=list(inventory), rootIds=sorted([ids['front']['id'], ids['tail']['id']] +
                        ([ids['tape']['id']] if phase == 'input' else [output] if final else [])),
                        books=books, originalCount=1 if phase == 'input' else 0,
                        device=dict(on=True, power=1, powerable=True, volume=.25 if final else .5,
                                    channel=95000 if final else 90000, micMuted=False, hasMedia=baseline,
                                    mediaIndex=7 if baseline else -1, mediaType=1,
                                    playing=baseline and case == 'eject-playing'),
                        outputs=[dict(id=output, type='Base.VHS_Retail', index=7, mediaType=1,
                                      recorded=True, root=True, count=1)] if final else [])
        setup_names = ['insert', 'play'] if case == 'eject-playing' else ['insert']
        expected = a.EDITED if mode == 'toolkit' else a.ORIGINAL
        ack_values = []; next_transaction = 1
        def command(name):
            nonlocal next_transaction
            book = name in ('front', 'tail'); cancelled = name == 'redundant' and mode == 'toolkit'
            kind_name = 'ISReadABook' if book else 'ISDeviceMediaAction' if name in ('insert', 'eject') else 'ISRadioAction'
            row = dict(name=name, type=kind_name, mode=a.MODES[name], duration=52800 if book else 30,
                       producer='native ISReadABook constructor' if book else 'native RWM callback',
                       started=not cancelled, progress=not cancelled, cancelled=cancelled)
            if not cancelled:
                row.update(startedAt=1000 + next_transaction * 100, effectiveDuration=row['duration'],
                           nativeDurationBefore=row['duration'],nativeDurationAfter=row['duration'],
                           durationSampleBefore=900 + next_transaction * 100, durationSampleAfter=950 + next_transaction * 100,
                           allocatedAt=950 + next_transaction * 100,durationSamples=2)
            if mode == 'toolkit' and name in ('volume', 'redundant'):
                row['preparation'] = preparation_proof(name, ids['tv'], cancelled)
            if name == 'eject': row.update(mediaAtStart=7, playingAtStart=case == 'eject-playing')
            if kind == 'mp' and not book and not cancelled:
                ack = dict(kind=kind_name, transaction=next_transaction,
                           token=f'{offset+next_transaction:08x}-1234-1234-1234-123456789abc', state='completed')
                row['ack'] = ack; ack_values.append((name, ack)); next_transaction += 1
            return row
        setup = [command(n) for n in setup_names]
        commands = [command(n) for n in a.ORIGINAL]
        by_name = dict(ack_values)
        acks = [dict(case=case, name=n, **{key: by_name[n][key] for key in ('kind', 'transaction', 'token')}, state=state)
                for n in setup_names + expected if n in by_name for state in ('started', 'completed')]
        baseline, final = snapshot('baseline'), snapshot('final')
        row = dict(suite='tv-controls', event='case', actor='client1', id=case, kind=kind, mode=mode, status='passed',
                   ids=copy.deepcopy(ids), clientPlacement=placement_proof(ids['origin']), input=snapshot('input'), baseline=copy.deepcopy(baseline),
                   authorityBaseline=copy.deepcopy(baseline), client=copy.deepcopy(final), server=copy.deepcopy(final),
                   setup=setup, commands=commands, initialQueue=list(a.ORIGINAL), editedQueue=list(expected), order=list(expected),
                   edit=dict(reordered=mode=='toolkit', cancelled=['redundant'] if mode=='toolkit' else [], untouched=True, atomic=True),
                   queueIdle=True, settleMilliseconds=1000)
        def physical(names):
            return [part for name in names for part in ([name + ':approach', name]
                    if mode == 'toolkit' and name in ('volume', 'redundant') else [name])]
        row.update(initialPhysicalQueue=physical(a.ORIGINAL), editedPhysicalQueue=physical(expected))
        return row, ids, baseline, final, acks

    def check(self, evidence, selection=None):
        row, ids, baseline, final, acks = evidence
        selection = selection or self.selection()
        return a.check_case(row, row['id'], selection, ids, baseline, final, acks)

    def test_placement_proofs_require_independent_roles_and_settled_squares(self):
        for kind in ('sp', 'mp'):
            selection = self.selection(kind)
            for location in ('client', 'authority'):
                for mutation in ('missing', 'wrong-role', 'teleports', 'unsettled', 'stale-square', 'target', 'motion'):
                    if location == 'authority' and kind == 'mp' and mutation == 'motion':
                        continue
                    with self.subTest(kind=kind, location=location, mutation=mutation):
                        evidence = self.evidence('eject-idle', kind)
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
                        self.assertTrue(self.check(evidence, selection))
        evidence = self.evidence('eject-idle', 'mp')
        row, ids = evidence[:2]
        # Ordinary replicated coordinates/timing can differ from the local receipt.
        ids['placementProof']['actual']['x'] += .25
        ids['placementProof']['stableMs'] = 600
        row['ids'] = copy.deepcopy(ids)
        self.assertEqual(self.check(evidence, self.selection('mp')), [])

    def test_approach_proof_and_physical_queue_fail_closed(self):
        for kind in ('sp', 'mp'):
            for location, value in (
                ('helper', 'walkAdjWall'), ('argumentCount', 4), ('keepActions', False), ('owned', False),
                ('constructor', False), ('resolver', False), ('sameOperation', False), ('started', False),
                ('completed', False), ('succeeded', False), ('children', 1), ('children', False),
                ('cancelled', True), ('name', 'other')):
                with self.subTest(kind=kind, field=location, value=value):
                    evidence = self.evidence('eject-idle', kind)
                    row = evidence[0]
                    command = next(c for c in row['commands'] if c['name'] == 'volume')
                    command['preparation'][location] = value
                    self.assertTrue(self.check(evidence, self.selection(kind)))
            for field in ('initialPhysicalQueue', 'editedPhysicalQueue'):
                evidence = self.evidence('eject-idle', kind)
                evidence[0][field] = list(evidence[0]['initialQueue'])
                self.assertTrue(self.check(evidence, self.selection(kind)))
            for field in ('preparation',):
                evidence = self.evidence('eject-idle', kind)
                next(c for c in evidence[0]['commands'] if c['name'] == 'volume').pop(field)
                self.assertTrue(self.check(evidence, self.selection(kind)))
            evidence = self.evidence('eject-idle', kind)
            next(c for c in evidence[0]['commands'] if c['name'] == 'volume')['preparation']['target']['x'] += 1
            self.assertTrue(self.check(evidence, self.selection(kind)))
            evidence = self.evidence('eject-idle', kind, 'native')
            next(c for c in evidence[0]['commands'] if c['name'] == 'volume')['preparation'] = preparation_proof('volume', evidence[1]['tv'])
            self.assertTrue(self.check(evidence, self.selection(kind, 'native')))

    def test_cancelled_dispatcher_cannot_execute_or_remain_in_physical_queue(self):
        for kind in ('sp', 'mp'):
            for mutation in ('started', 'completed', 'retained'):
                evidence = self.evidence('eject-idle', kind)
                row = evidence[0]
                preparation = next(c for c in row['commands'] if c['name'] == 'redundant')['preparation']
                if mutation == 'retained': row['editedPhysicalQueue'].insert(1, 'redundant:approach')
                else: preparation[mutation] = True
                self.assertTrue(self.check(evidence, self.selection(kind)))

    def test_lua_preparation_proves_exact_intent_and_observes_synchronous_completion(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/tv-controls/client/ZZTVControls.lua').read_text()
        helper = 'local preparations={}' + source.split('local preparations={}', 1)[1].split('local function nativeUI', 1)[0]
        prefix = """
            local native=false;local watchPreparations
            local player={};local square={getX=function()return 10 end,getY=function()return 20 end,getZ=function()return 0 end}
            local device={getSquare=function()return square end}
            local q={queue={},indexOf=function(self,a)for i,v in ipairs(self.queue)do if v==a then return i end end;return -1 end}
            local function queue()return q end
            getPlayer=function()return player end;luautils={}
            local observers
            local T={ActionQueueApproach={isAction=function(a)return not a.foreign end,capture=function(a)return not a.unsealed and not a.action end},
                ActionQueueOperations={commandConstructionTrusted=function()return true end},
                ActionQueueLifecycle={registerObserver=function(_,value)observers=value;return true end}}
            local function action()
                return {character=player,toolkitQueueOperation={},_numAddedActions=0,
                    toolkitQueueCommand={snapshot={binding={owner=luautils,name='walkAdj'},args={n=3,player,square,true}}}}
            end
        """
        suffix = """
            watchPreparations()
            local first=action()
            local proof=capturePreparation(first,'anchor',device)
            -- Native add may start/resolve the anchor before its setter exists.
            q.current=first;observers.started(first);first.action={}
            assert(observers.begin(first,'perform')==nil);observers.finish(first,'perform',true)
            q.current=nil
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
            pairPreparation(walked,{toolkitQueueOperation=walked.toolkitQueueOperation})
            q.current=walked;observers.started(walked);walked.action={};walked._numAddedActions=1
            assert(not pcall(observers.begin,walked,'perform'));observers.finish(walked,'perform',true)
            q.current=nil;assert(not pcall(verifyPreparations))
        """
        lua = LuaRuntime()
        lua.execute(prefix + helper + suffix)

    def test_lua_prepare_sends_only_after_one_local_settled_placement(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/tv-controls/client/ZZTVControls.lua').read_text()
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
        source = (ROOT / 'tests/native_queue/tv-controls/server/ZZTVControlsServer.lua').read_text()
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
                F={prepare=function(...)calls=calls+1;return {ids={case='eject-idle'}}end}
                package.preload.QueueEnergyPlacement=function()return P end
                package.preload.QueueTVControls=function()return F end
                package.preload.QueueHealthEvents=function()return {encode=function()return '{}'end}end
                package.preload.QueueTestSelection=function()return {cases={'eject-idle'},mode='toolkit'}end
            """)
            lua.execute(source)
            lua.execute("callbacks.command('TVControlsTest','Prepare',player,{case='eject-idle',placement=target,clientPlacement={mode='local'}});assert(calls==0);callbacks.tick();assert(calls==0)")
            lua.globals().fresh = not left_tile
            lua.execute('settled=true;callbacks.tick()')
            self.assertEqual(lua.globals().calls, 0 if left_tile else 1)
            self.assertEqual(lua.globals().lastCommand, 'Failed' if left_tile else 'Prepared')
        lua = LuaRuntime()
        lua.execute("isServer=function()return true end;package.preload.QueueEnergyPlacement=function()return {target=function(t)return t end,at=function()return false end}end")
        fixture = lua.execute((ROOT / 'tests/native_queue/tv-controls/shared/QueueTVControls.lua').read_text())
        # No getCell/item constructors exist: precondition must fail before scene or inventory mutations.
        with self.assertRaisesRegex(Exception, 'left settled placement'):
            fixture.prepare(lua.table(), 'eject-idle', 'toolkit', lua.table(x=10, y=20, z=0))

    def test_all_native_toolkit_sp_host_cases(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                selection=self.selection(kind,mode);a.validate(selection)
                for case in a.CASES:
                    with self.subTest(kind=kind,mode=mode,case=case):
                        self.assertEqual(self.check(self.evidence(case,kind,mode),selection),[])

    def test_causal_mutations_fail(self):
        mutations = {
            'boolean original count': lambda r: r['input'].update(originalCount=True),
            'original not debited': lambda r: r['baseline'].update(originalCount=1),
            'wrong seed input': lambda r: r['input'].update(originalCount=0),
            'wrong playback baseline': lambda r: r['baseline']['device'].update(playing=False),
            'playing vanished before eject': lambda r: r['commands'][6].update(playingAtStart=False),
            'empty wrong cassette': lambda r: r['commands'][6].update(mediaAtStart=9),
            'client retained media': lambda r: r['client']['device'].update(hasMedia=True),
            'server retained media': lambda r: r['server']['device'].update(hasMedia=True),
            'native stop never settled': lambda r: r['client']['device'].update(playing=True),
            'returned old ID': lambda r: r['client']['outputs'][0].update(id=r['ids']['tape']['id']),
            'wrong VHS index': lambda r: r['client']['outputs'][0].update(index=9),
            'wrong VHS type': lambda r: r['client']['outputs'][0].update(type='Base.VHS_Home'),
            'old bag VHS masquerades as output': lambda r: r['baseline']['carriedIds'].append(r['client']['outputs'][0]['id']),
            'nested output': lambda r: r['client']['outputs'][0].update(root=False),
            'duplicate output': lambda r: r['client']['outputs'][0].update(count=2),
            'missing output': lambda r: r['client'].update(outputs=[]),
            'extra output': lambda r: r['client']['outputs'].append(dict(r['client']['outputs'][0], id=999)),
            'unrelated inventory lost': lambda r: r['baseline']['rootIds'].append(999),
            'unrelated inventory added': lambda r: r['client']['rootIds'].append(999),
            'tail cancelled': lambda r: r['client']['books']['tail'].update(pages=218),
            'wrong tail ID': lambda r: r['client']['books']['tail'].update(id=999),
            'server tail uncommitted': lambda r: r['server']['books']['tail'].update(characterPages=218),
            'client volume wrong': lambda r: r['client']['device'].update(volume=.75),
            'server volume wrong': lambda r: r['server']['device'].update(volume=.75),
            'server channel wrong': lambda r: r['server']['device'].update(channel=90000),
            'power lost': lambda r: r['client']['device'].update(on=False),
            'NaN power': lambda r: r['client']['device'].update(power=float('nan')),
            'world object replaced': lambda r: r['client']['tv'].update(index=8),
            'original order retained': lambda r: r.update(editedQueue=list(a.ORIGINAL)),
            'tail start lost': lambda r: r['order'].pop(),
            'pending edit executed effect': lambda r: r['edit'].update(untouched=False),
            'cancelled setter started': lambda r: r['commands'][2].update(started=True),
            'instant duration': lambda r: r['commands'][6].update(effectiveDuration=0),
            'Host receipt rejected': lambda r: r['commands'][6]['ack'].update(state='rejected'),
            'allocation bracket widened': lambda r: r['commands'][6].update(nativeDurationAfter=999),
            'allocation bracket stale': lambda r: r['commands'][6].update(durationSampleBefore=99999999),
            'allocation bracket NaN': lambda r: r['commands'][6].update(nativeDurationBefore=float('nan')),
            'duration sample missing': lambda r: r['commands'][6].pop('nativeDurationBefore'),
            'allocation time changed': lambda r: r['commands'][6].update(allocatedAt=1),
            'native duration changed': lambda r: r['commands'][6].update(effectiveDuration=1),
            'wrong UI producer': lambda r: r['commands'][6].update(producer='synthetic complete'),
        }
        for label, change in mutations.items():
            with self.subTest(label=label):
                evidence=self.evidence('eject-playing');change(evidence[0])
                self.assertTrue(self.check(evidence),label)

    def test_native_duration_is_inside_independently_sampled_small_bracket(self):
        evidence=self.evidence('eject-idle');tail=evidence[0]['commands'][-1]
        # Observed R2 native creation differs from its later body-temperature
        # sample. Accept the measured allocation interval, never an arbitrary
        # percentage window around the late sample.
        tail.update(duration=79200,nativeDurationBefore=79252.2,nativeDurationAfter=79252.43740081787,
                    effectiveDuration=79252.30522155762,durationSamples=20)
        self.assertEqual(self.check(evidence),[])
        for value in (79251,79253.2,1,0,float('inf')):
            with self.subTest(value=value):
                mutated=copy.deepcopy(evidence);mutated[0]['commands'][-1]['effectiveDuration']=value
                self.assertTrue(self.check(mutated))
        tail.update(nativeDurationBefore=79251,nativeDurationAfter=79253.2)
        self.assertTrue(self.check(evidence),'a large interval cannot justify an otherwise in-range duration')

    def test_actual_lua_allocation_capture_is_read_only_and_sealed(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime()
        source=(ROOT/'tests/native_queue/tv-controls/client/ZZTVControls.lua').read_text()
        helper='local function finite'+source.split('local function finite',1)[1].split('local function register',1)[0]
        capture=lua.execute('local now=function()return 100 end\n'+helper+'\nreturn captureDuration')
        check=lua.eval("""function(capture)
            local reads=0
            local action={action={},maxTime=79252.30522155762,
                adjustMaxTime=function(self,declared)assert(declared==79200);reads=reads+1;return 79252.43740081787 end}
            local row={name='tail',duration=79200,nativeDurationBefore=79252.2,durationSampleBefore=90,durationSamples=2}
            capture(action,row)
            assert(row.effectiveDuration==79252.30522155762 and row.allocatedAt==100 and reads==1)
            assert(action.maxTime==79252.30522155762,'measurement mutated native duration')
            capture(action,row);assert(reads==1,'allocated proof must not be refreshed from later modifiers')
            action.maxTime=79252.4
            assert(not pcall(capture,action,row),'allocated duration mutation must fail')
            local pending={maxTime=79200,adjustMaxTime=function()error('pending capture cannot simulate create')end}
            capture(pending,{})
        end""")
        check(capture)

    def test_wire_receipts_cannot_be_missing_duplicated_or_reordered(self):
        for mutation in ('drop','duplicate','reverse','foreign','terminal'):
            evidence=self.evidence('eject-playing');acks=evidence[-1]
            if mutation=='drop':acks.pop()
            elif mutation=='duplicate':acks.append(copy.deepcopy(acks[-1]))
            elif mutation=='reverse':acks.reverse()
            elif mutation=='foreign':acks[-1]['token']='deadbeef-1234-1234-1234-123456789abc'
            else:acks[-1]['state']='rejected'
            self.assertTrue(self.check(evidence),mutation)

    def test_authority_must_be_independent_raw_readback(self):
        evidence=self.evidence('eject-playing');evidence[0]['server']['outputs'][0]['id']=999
        self.assertTrue(self.check(evidence))
        evidence=self.evidence('eject-playing');evidence[0]['authorityBaseline']['device']['playing']=False
        self.assertTrue(self.check(evidence))

    def test_full_two_case_log_and_authority_order(self):
        selection=self.selection()
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);client=['[QUEUE_CHECK] '+json.dumps(dict(suite='tv-controls',event='setup',cases=list(a.CASES),queueEnabled=True,nativeDurations=True))];server=[]
            for case in a.CASES:
                row,ids,baseline,final,acks=self.evidence(case)
                client.append(a.PREFIX+'CLIENT_PLACEMENT '+json.dumps({'case': case, 'proof': row['clientPlacement']}))
                client.append('[QUEUE_CHECK] '+json.dumps(row))
                client.extend(a.PREFIX+'ACK '+json.dumps(v) for v in acks)
                for marker,value in [('PREPARED',ids),('BASELINE',baseline),('VERIFIED',final)]:
                    server.append(a.PREFIX+marker+' '+json.dumps(value))
            client.append('[QUEUE_CHECK] '+json.dumps(dict(suite='tv-controls',event='complete',cases=list(a.CASES),performed=2,failed=0,skipped=0)))
            client.append(a.PREFIX+'COMPLETE '+json.dumps({'cases':list(a.CASES)}))
            (root/'client1-launch.log').write_text('\n'.join(client))
            (root/'server-launch.log').write_text('\n'.join(server))
            self.assertEqual(a.verify(root,selection,{})['issues'],[])
            for mutation in ('missing', 'duplicate', 'reverse', 'foreign', 'mismatched'):
                changed = client.copy()
                positions = [i for i, line in enumerate(changed) if line.startswith(a.PREFIX+'CLIENT_PLACEMENT ')]
                if mutation == 'missing': changed.pop(positions[0])
                elif mutation == 'duplicate': changed.insert(positions[0], changed[positions[0]])
                elif mutation == 'reverse': changed[positions[0]], changed[positions[1]] = changed[positions[1]], changed[positions[0]]
                else:
                    value = json.loads(changed[positions[0]].split('CLIENT_PLACEMENT ', 1)[1])
                    if mutation == 'foreign': value['case'] = 'unknown'
                    else: value['proof']['actual']['x'] += .25
                    changed[positions[0]] = a.PREFIX+'CLIENT_PLACEMENT '+json.dumps(value)
                (root/'client1-launch.log').write_text('\n'.join(changed))
                self.assertTrue(a.verify(root,selection,{})['issues'], mutation)
            (root/'client1-launch.log').write_text('\n'.join(client))
            bad_client=client.copy()
            bad=json.loads(bad_client[2].split('[QUEUE_CHECK] ',1)[1]);bad['actor']='client2'
            bad_client[2]='[QUEUE_CHECK] '+json.dumps(bad)
            (root/'client1-launch.log').write_text('\n'.join(bad_client))
            self.assertTrue(a.verify(root,selection,{})['issues'])
            (root/'client1-launch.log').write_text('\n'.join(client))
            (root/'server-launch.log').write_text('\n'.join(reversed(server)))
            self.assertTrue(a.verify(root,selection,{})['issues'])

    def test_selection_is_fresh_full_pack_two_cases_only(self):
        for key,value in [('cases',['eject-idle']),('cases',list(reversed(a.CASES))),('clients',2),('mods',[]),('languages',['RU'])]:
            selection=self.selection();selection[key]=value
            with self.assertRaises(ValueError):a.validate(selection)
        selection=self.selection();selection['options']={}
        with self.assertRaises(ValueError):a.validate(selection)

    def test_registration_and_staged_sources_are_complete(self):
        from queue_checks import adapters
        self.assertIs(adapters.get('tv-controls'), a)
        self.assertEqual(adapters.get('tv-controls').definitions()['tv-controls']['cases'],
                         json.loads((ROOT/'tests/native_queue/catalog.json').read_text())['suites']['tv-controls']['cases'])
        self.assertTrue(all(path.is_file() for path in a.sources(ROOT,self.selection())))
        with tempfile.TemporaryDirectory() as temp:
            cache=Path(temp);lua=cache/'mods/ActionQueueTest/42/media/lua'
            for side in ('client','server','shared'):(lua/side).mkdir(parents=True)
            runtime={'roles':{'client1':{'cache':str(cache)}}}
            a.stage(ROOT,None,None,None,self.selection(),None,runtime)
            self.assertTrue((lua/'client/ZZStartup.lua').is_file())
            self.assertTrue((lua/'server/ZZStartupServer.lua').is_file())
            self.assertTrue((lua/'shared/QueueHealthEvents.lua').is_file())
            self.assertEqual(runtime['fixture']['sandbox']['MinutesPerPage'],2.0)


    def test_fixture_approach_uses_native_corrected_target_without_mutation(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime()
        lua.execute("package.preload.QueueEnergyPlacement=function()return {}end")
        fixture=lua.execute((ROOT/'tests/native_queue/tv-controls/shared/QueueTVControls.lua').read_text())
        check=lua.eval("""function(fixture)
            local calls=0
            local target={getX=function()return 9 end,getY=function()return 20 end,getZ=function()return 0 end}
            local square={canReachTo=function(self,value) assert(value==target);return true end}
            local player={getX=function()return 10.5 end,getY=function()return 20.5 end,
                getZ=function()return 0 end,getSquare=function()return square end}
            local tv={getSquare=function()return target end}
            luautils={getCorrectSquareForWall=function(p,s)assert(p==player and s==target);calls=calls+1;return target end}
            local state={player=player,tv=tv}
            local value=fixture.approach(state)
            assert(value.reachable and value.canReach and value.dx==1 and value.dy==0 and calls==1)
            -- A native redirected target two tiles from the actor must wait;
            -- read-only readiness cannot move the actor or suppress a real walk.
            player.getX=function()return 7.5 end
            value=fixture.approach(state);assert(not value.reachable and value.dx==2 and calls==2)
            player.getX=function()return 10.5 end;square.canReachTo=function()return false end
            value=fixture.approach(state);assert(not value.reachable and not value.canReach and calls==3)
        end""")
        check(fixture)

    def test_lua_modules_compile_without_running_game(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime();compile_chunk=lua.eval('function(source,name) return assert(loadstring(source,name)) end')
        for path in (ROOT/'tests/native_queue/tv-controls').rglob('*.lua'):
            compile_chunk(path.read_text(),str(path))


if __name__=='__main__':unittest.main()
