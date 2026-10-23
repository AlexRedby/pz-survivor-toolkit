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


class TVControlsTests(unittest.TestCase):
    def selection(self, kind='mp', mode='toolkit'):
        return dict(suite='tv-controls', cases=list(a.CASES), kind=kind, mode=mode,
                    clients=1, languages=['EN'], mods=list(a.MODS), options={'mp_host': True} if kind == 'mp' else {})

    def evidence(self, case, kind='mp', mode='toolkit'):
        offset = 0 if case == 'eject-idle' else 10
        ids = dict(case=case, mode=mode, tv=dict(x=10, y=20, z=0, index=1), origin=dict(x=9, y=20, z=0),
                   front=dict(id=101+offset, type='Base.BookCarpentry1', pages=220, initial=218),
                   tail=dict(id=102+offset, type='Base.BookCooking1', pages=220, initial=218),
                   tape=dict(id=103+offset, type='Base.VHS_Retail', index=7, mediaType=1))
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
                   ids=copy.deepcopy(ids), input=snapshot('input'), baseline=copy.deepcopy(baseline),
                   authorityBaseline=copy.deepcopy(baseline), client=copy.deepcopy(final), server=copy.deepcopy(final),
                   setup=setup, commands=commands, initialQueue=list(a.ORIGINAL), editedQueue=list(expected), order=list(expected),
                   edit=dict(reordered=mode=='toolkit', cancelled=['redundant'] if mode=='toolkit' else [], untouched=True, atomic=True),
                   queueIdle=True, settleMilliseconds=1000)
        return row, ids, baseline, final, acks

    def check(self, evidence, selection=None):
        row, ids, baseline, final, acks = evidence
        selection = selection or self.selection()
        return a.check_case(row, row['id'], selection, ids, baseline, final, acks)

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
                client.append('[QUEUE_CHECK] '+json.dumps(row))
                client.extend(a.PREFIX+'ACK '+json.dumps(v) for v in acks)
                for marker,value in [('PREPARED',ids),('BASELINE',baseline),('VERIFIED',final)]:
                    server.append(a.PREFIX+marker+' '+json.dumps(value))
            client.append('[QUEUE_CHECK] '+json.dumps(dict(suite='tv-controls',event='complete',cases=list(a.CASES),performed=2,failed=0,skipped=0)))
            client.append(a.PREFIX+'COMPLETE '+json.dumps({'cases':list(a.CASES)}))
            (root/'client1-launch.log').write_text('\n'.join(client))
            (root/'server-launch.log').write_text('\n'.join(server))
            self.assertEqual(a.verify(root,selection,{})['issues'],[])
            bad_client=client.copy()
            bad=json.loads(bad_client[1].split('[QUEUE_CHECK] ',1)[1]);bad['actor']='client2'
            bad_client[1]='[QUEUE_CHECK] '+json.dumps(bad)
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
