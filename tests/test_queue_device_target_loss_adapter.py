"""Loss receipts must distinguish observed baseline behavior from safe qualification."""
import copy
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import device_target_loss as adapter


def proof(target, mode):
    actual = dict(target, square=dict(target), currentSquare=dict(target))
    if mode == 'local':
        actual.update(queued=0, timed=False, moving=False, hasPath=False, deferredX=0, deferredY=0)
    return dict(mode=mode, target=dict(target), actual=actual, teleports=int(mode == 'local'),
                stableMs=500, quietMs=500 if mode == 'local' else 0, elapsedMs=1500)


class DeviceTargetLossTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def selection(self, case='tv-remove', kind='sp', mode='toolkit', expectation='capture'):
        return dict(suite='device-target-loss', cases=[case], kind=kind, mode=mode, clients=1,
                    languages=['EN'], mods=list(adapter.MODS), options=dict(
                        device_target_loss_expect=expectation, **({'mp_host': True} if kind == 'mp' else {})))

    def evidence(self, case='tv-remove', kind='sp', mode='toolkit', expectation='capture', stale=False, tail=True):
        origin = dict(x=10, y=20, z=0)
        walking = case in ('radio-walk-remove', 'tv-walk-move')
        ids = dict(case=case, mode=mode, key='device-target-loss:' + case + ':100',
            **{'class': 'IsoTelevision' if case.startswith('tv-') else 'IsoRadio'},
            old=dict(origin, x=2 if walking else 9), destination=dict(origin, x=1 if walking else 11),
            generator=dict(origin, x=5 if walking else 10, y=21), index=1,
            origin=origin, placementProof=proof(origin, 'replica' if kind == 'mp' else 'local'),
            hold=dict(id=100, type='Base.BookForaging1', pages=220, initial=216),
            tail=dict(id=101, type='Base.BookTrapping1', pages=220, initial=218))
        moved = {'tv-remove': False, 'tv-move': True, 'radio-remove': False, 'radio-move': True,
                 'radio-walk-remove': False, 'tv-walk-move': True}[case]
        if walking:
            ids['walkLayout'] = dict(distance=8, minX=-10, maxX=1, minY=-1, maxY=1, chosenBeforePlacement=True)

        def snapshot(initial=False, authority=False, after_mutation=False):
            present = initial or moved
            same = initial or moved and (authority or kind == 'sp')
            values = dict(volume=.5 if initial or after_mutation or not stale else .75,
                channel=90000, on=True, battery=False, media=False, power=1, powered=True)
            books = {}
            for name, spec in ((n, ids[n]) for n in ('hold', 'tail')):
                pages = spec['initial'] if initial or after_mutation or name == 'tail' and not tail else spec['pages']
                books[name] = dict(id=spec['id'], type=spec['type'], root=True, count=1,
                                   pages=pages, characterPages=pages)
            return dict(case=case, key=ids['key'], generatorPresent=True, oldPresent=initial,
                destinationPresent=not initial and moved, heldMemberOld=initial,
                heldMemberDestination=not initial and same, heldSquare=ids['old'] if initial or not same else ids['destination'],
                heldIndex=1 if same else -1, heldDataSame=True, heldDataParentSame=True,
                liveSameObject=same, liveSameData=same, held=copy.deepcopy(values),
                live=copy.deepcopy(values) if present else False, books=books)

        before = snapshot(initial=True)
        mutation = dict(case=case, key=ids['key'], operation='move' if moved else 'remove',
            sameAuthorityObject=True, sameAuthorityData=True, before=snapshot(initial=True, authority=True),
            after=snapshot(authority=True, after_mutation=True), at=1200)
        names = ['hold', *(['setter:approach'] if mode == 'toolkit' else []), 'setter', 'tail']
        commands = []
        for i, name in enumerate(names):
            started = name == 'hold' or name == 'tail' and tail or name.startswith('setter') and stale
            duration = -1 if name.endswith('approach') else 30 if name == 'setter' else 10000
            row = dict(name=name, type='ISReadABook' if name in ('hold', 'tail') else
                'ISRadioAction' if name == 'setter' else 'ISQueueActionsAction', duration=duration,
                started=started, progress=started and name != 'setter:approach', starts=int(started),
                performed=started and mode == 'toolkit', stopped=False, allocated=started)
            if started:
                row.update(startedAt=1000 + i * 1000, performAt=2000 + i * 1000,
                    effectiveDuration=duration, nativeDurationExpected=duration)
                if row['performed']:
                    row['finishedAt'] = 2001 + i * 1000
                if row['progress']:
                    row['progressAt'] = row['startedAt'] + 10
            if name == 'setter':
                row.update(mode='SetVolume', value=.75, targetKey=ids['key'], originalDevice=True,
                           originalData=True, pendingAtMutate=True, mutationRequestedAt=1100)
            commands.append(row)
        server = snapshot(authority=True)
        cleanup = dict(case=case, key=ids['key'], objectsRemoved=True, generatorRemoved=True, booksRemoved=True)
        row = dict(event='case', suite='device-target-loss', id=case, actor='client1', kind=kind, mode=mode,
            status='captured' if expectation == 'capture' else 'passed', expectation=expectation,
            safeOutcome=mode == 'toolkit' and not stale and tail, ids=ids, clientPlacement=proof(origin, 'local'), before=before,
            initialQueue=names, mutation=mutation, observed=snapshot(after_mutation=True), observedAt=1500,
            commands=commands, acks=[], client=snapshot(), server=server, queueIdle=True, queueTimedOut=False,
            recovery='none', settleMilliseconds=1500, cleanup=cleanup, cleanupObserved=True,
            cleanupSettleMilliseconds=1500, nativeCallbacksUnchanged=True, originalSetterBinding=True)
        if walking:
            mutation['at'] = 3200
            row['observedAt'] = 3500
            for command in commands:
                if command['name'] == 'setter':
                    command['mutationRequestedAt'] = 3100
                    if command['started']:
                        command.update(startedAt=5500, progressAt=5510, performAt=5600)
                        if mode == 'toolkit': command['finishedAt'] = 5601
                elif command['name'] == 'setter:approach':
                    command.update(started=True, starts=1, allocated=True, progress=False, performed=True,
                        startedAt=2100, performAt=2200, finishedAt=2201, effectiveDuration=-1, nativeDurationExpected=-1)
                elif command['name'] == 'tail' and command['started']:
                    command.update(startedAt=6000, progressAt=6010, performAt=7000)
                    if mode == 'toolkit': command['finishedAt'] = 7001
            if mode == 'native': row['initialQueue'] = ['hold', 'setter:walk', 'setter', 'tail']
            child = dict(name='setter:walk', type='ISWalkToTimedAction', duration=-1, starts=1, started=True,
                progress=True, allocated=True, performed=mode == 'toolkit', stopped=False, effectiveDuration=-1,
                nativeDurationExpected=-1, sameOperation=True, nativeCallbacks=True, nativeHandleStable=True,
                retired=True, destination=dict(x=3, y=20, z=0), startPosition=dict(x=10, y=20, z=0),
                startedAt=3000, nativeAllocatedAt=3001, progressAt=3010, performAt=5000, retiredAt=5010,
                resultSucceeded=True, atDestination=True, arrival=dict(x=3, y=20, z=0))
            if mode == 'toolkit': child['finishedAt'] = 5001
            def paid_event(at):
                return dict(at=at, position=dict(x=9.8, y=20, z=0), currentNativeSame=True,
                    bodyUnallocated=True, bodyUnstarted=True, sameOperation=True)
            row['paidApproach'] = dict(schema=1, producer='native RWM walkAdj', mode=mode, children=1,
                child=child, initialPending=True, tailIndependent=True, mutation=paid_event(3100), observed=paid_event(3500))
        return row, ids, mutation, server, cleanup

    def verify(self, selection, evidence, omit=None, completion='[DEVICE_TARGET_LOSS] COMPLETE'):
        row, ids, mutation, server, cleanup = evidence
        raw = ''.join('[DEVICE_TARGET_LOSS] ' + name + ' ' + json.dumps(value) + '\n'
            for name, value in [('PREPARED', ids), ('MUTATED', mutation), ('VERIFIED', server), ('CLEANED', cleanup)]
            if name != omit)
        text = '[QUEUE_CHECK] ' + json.dumps(row) + '\n' + completion + '\n'
        text += '[DEVICE_TARGET_LOSS] CLIENT_PLACEMENT ' + json.dumps(dict(case=row['id'], proof=row['clientPlacement'])) + '\n'
        (self.root / 'client1-launch.log').write_text(text + (raw if selection['kind'] == 'sp' else ''))
        (self.root / 'server-launch.log').write_text(raw if selection['kind'] == 'mp' else '')
        return adapter.verify(self.root, selection, {})

    def test_baseline_capture_does_not_assume_bug_or_claim_effect_qualification(self):
        for case, kind, mode, stale, tail in itertools.product(adapter.CASES, ('sp', 'mp'), ('native', 'toolkit'), (False, True), (False, True)):
            with self.subTest(case=case, kind=kind, mode=mode, stale=stale, tail=tail):
                selection = self.selection(case, kind, mode)
                adapter.validate(selection)
                result = self.verify(selection, self.evidence(case, kind, mode, stale=stale, tail=tail))
                self.assertEqual(result['issues'], [])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['effectsVerified'])

    def test_safe_gate_requires_unchanged_old_and_live_data_and_real_native_tail(self):
        for case, kind, stale, tail in itertools.product(adapter.CASES, ('sp', 'mp'), (False, True), (False, True)):
            with self.subTest(case=case, kind=kind, stale=stale, tail=tail):
                selection = self.selection(case, kind, expectation='safe')
                result = self.verify(selection, self.evidence(case, kind, expectation='safe', stale=stale, tail=tail))
                self.assertEqual(bool(result['issues']), stale or not tail)

    def test_safe_gate_rejects_any_setter_admission_even_with_unchanged_endpoints(self):
        for case, kind, admission in itertools.product(adapter.CASES, ('sp', 'mp'), ('started', 'allocated', 'performed', 'perform-entry', 'ack')):
            with self.subTest(case=case, kind=kind, admission=admission):
                evidence = self.evidence(case, kind, expectation='safe')
                row = evidence[0]
                setter = next(command for command in row['commands'] if command['name'] == 'setter')
                if admission == 'started':
                    setter.update(started=True, starts=1, startedAt=3000)
                elif admission == 'allocated':
                    setter.update(allocated=True, effectiveDuration=30, nativeDurationExpected=30)
                elif admission == 'performed':
                    setter.update(started=True, starts=1, startedAt=3000, performAt=4000,
                                  performed=True, finishedAt=4001)
                elif admission == 'perform-entry':
                    setter['performAt'] = 4000
                else:
                    row['acks'] = [dict(kind='ISRadioAction', state='started', transaction=1, token='owned', at=3000)]
                # No device data, tail effect or cleanup fact changes here.
                self.assertEqual(row['client']['held']['volume'], .5)
                self.assertEqual(row['server']['held']['volume'], .5)
                self.assertTrue(self.verify(self.selection(case, kind, expectation='safe'), evidence)['issues'])

    def test_native_capture_requires_no_invented_finish_success(self):
        for kind, case in itertools.product(('sp', 'mp'), adapter.CASES):
            evidence = self.evidence(case, kind, 'native', stale=True)
            for command in evidence[0]['commands']:
                self.assertFalse(command['performed'])
                self.assertNotIn('finishedAt', command)
            self.assertEqual(self.verify(self.selection(case, kind, 'native'), evidence)['issues'], [])

    def test_capture_accepts_only_actual_ordered_native_terminal_ack_states(self):
        token = '00000000-0000-0000-0000-000000000001'
        for terminal, valid in [('completed', True), ('canceled', True), ('rejected', True), ('cancelled', False), ('failed', False)]:
            with self.subTest(terminal=terminal):
                evidence = self.evidence('radio-move', 'mp', stale=True)
                row = evidence[0]
                setter = next(command for command in row['commands'] if command['name'] == 'setter')
                setter['ackToken'] = token
                row['acks'] = [dict(kind='ISRadioAction', token=token, transaction=1, state=state, at=4000+i)
                               for i, state in enumerate(('started', terminal))]
                result = self.verify(self.selection('radio-move', 'mp'), evidence)
                self.assertEqual(not result['issues'], valid)
        for states in (['completed'], ['canceled'], ['rejected'], ['completed', 'started']):
            evidence = self.evidence('radio-move', 'mp', stale=True)
            evidence[0]['acks'] = [dict(kind='ISRadioAction', token=token, transaction=1, state=state, at=4000+i)
                                   for i, state in enumerate(states)]
            self.assertTrue(self.verify(self.selection('radio-move', 'mp'), evidence)['issues'])

    def test_lua_diagnostic_observers_always_return_nil_without_phase_authorization(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/device-target-loss/client/ZZDeviceTargetLoss.lua').read_text()
        helper = 'local observerError' + source.split('local observerError', 1)[1].split('local function checkCallbacks()', 1)[0]
        lua = LuaRuntime()
        lua.execute("""
            local tracked={};local state={};local now=function()return 1000 end
            T={ActionQueueLifecycle={registerObserver=function(id,observer)
                assert(id=='fixture.device-target-loss');diagnostic=observer;return true
            end}}
        """ + helper + """
            watch()
            local action={adjustMaxTime=function(_,duration)return duration end}
            local row={name='hold',starts=0,started=false,performed=false,duration=30}
            tracked[action]=row
            local authorization=false
            if diagnostic.started(action)==true then authorization=true end
            if diagnostic.begin(action,'perform')==true then authorization=true end
            assert(not authorization and row.started and row.performAt==1000)
            assert(row.nativeDurationExpected==30)
            assert(not row.performed,'perform entry fabricated completion success')
            assert(diagnostic.finish(action,'perform',true)==nil and row.performed)
            assert(diagnostic.begin({},'perform')==nil,'foreign diagnostic callback authorized tracking')
            assert(diagnostic.started(action)==nil and observerError,'observer failure leaked permission')
            assert(guarded(function()return true end)()==nil,'diagnostic result leaked lifecycle authorization')
        """)

    def test_lua_duration_oracle_uses_admission_modifier_before_native_creation(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/device-target-loss/client/ZZDeviceTargetLoss.lua').read_text()
        helpers = 'local observerError' + source.split('local observerError', 1)[1].split('local function begin()', 1)[0]
        lua = LuaRuntime()
        lua.execute("""
            local tracked,callbacks,walkBank={},{},nil
            local unchangedFunctions=function()end
            local q={};local queue=function()return q end
            local now=function()return 1000 end
            local T={ActionQueueLifecycle={registerObserver=function(_,observer)diagnostic=observer;return true end}}
        """ + helpers + """
            watch()
            local duration=79200
            local modifier=79298.83232116699/duration
            local calls=0
            local action={adjustMaxTime=function(_,value)calls=calls+1;return value*modifier end}
            local row={name='tail',duration=duration,starts=0,started=false,allocated=false}
            tracked[action]=row
            assert(diagnostic.started(action)==nil and not observerError and action.action==nil)
            local admissionExpected=duration*modifier
            action.maxTime=admissionExpected;action.action={}
            -- A real next-tick modifier drift used to report a false retiming.
            modifier=79298.92673492432/duration
            assert(math.abs(duration*modifier-admissionExpected)>.001)
            checkCallbacks()
            assert(calls==1 and row.nativeDurationExpected==admissionExpected and row.effectiveDuration==admissionExpected)
            assert(action.maxTime==admissionExpected,'fixture retimed native work')
            checkCallbacks();assert(calls==1)
            action.maxTime=admissionExpected+.01
            assert(not pcall(checkCallbacks),'actual allocated-duration mutation was accepted')
        """)

    def test_selection_rejects_unqualified_topologies_controls_and_case_order(self):
        for key, value in [('clients', 2), ('kind', 'server'), ('mode', 'fake'), ('languages', ['RU']),
                           ('mods', []), ('cases', ['radio-remove', 'tv-remove'])]:
            selection = self.selection(); selection[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): adapter.validate(selection)
        for options in ({'mp_host': False}, {'world_template': '/tmp/world'}, {'device_target_loss_expect': 'guess'}):
            selection = self.selection(kind='mp'); selection['options'].update(options)
            with self.subTest(options=options), self.assertRaises(ValueError): adapter.validate(selection)
        with self.assertRaises(ValueError): adapter.validate(self.selection(mode='native', expectation='safe'))

    def test_optional_paid_bank_preserves_default_four_and_accepts_explicit_ordered_six(self):
        self.assertEqual(adapter.CASES, ('tv-remove', 'tv-move', 'radio-remove', 'radio-move'))
        selection = self.selection(); selection['cases'] = list(adapter.ALL_CASES)
        with self.assertRaises(ValueError): adapter.validate(selection)
        selection['options']['device_target_loss_walk'] = True
        adapter.validate(selection)
        for cases in ([adapter.WALK_CASES[0]], list(adapter.CASES)):
            selection['cases'] = cases
            with self.assertRaises(ValueError): adapter.validate(selection)
        for case, kind, mode, stale, tail in itertools.product(adapter.WALK_CASES, ('sp', 'mp'), ('native', 'toolkit'), (False, True), (False, True)):
            with self.subTest(case=case, kind=kind, mode=mode, stale=stale, tail=tail):
                result = self.verify(self.selection(case, kind, mode), self.evidence(case, kind, mode, stale=stale, tail=tail))
                self.assertEqual(result['issues'], [])

    def test_paid_safe_gate_requires_original_successful_walk_and_pending_body_at_loss(self):
        changes = [
            lambda row: row['paidApproach'].update(children=0),
            lambda row: row['paidApproach'].update(tailIndependent=False),
            lambda row: row['paidApproach']['child'].update(starts=2),
            lambda row: row['paidApproach']['child'].update(sameOperation=False),
            lambda row: row['paidApproach']['child'].update(nativeHandleStable=False),
            lambda row: row['paidApproach']['child'].update(nativeCallbacks=False),
            lambda row: row['paidApproach']['child'].update(duration=1),
            lambda row: row['paidApproach']['child'].update(progress=False),
            lambda row: row['paidApproach']['child'].update(resultSucceeded=False),
            lambda row: row['paidApproach']['child'].update(atDestination=False),
            lambda row: row['paidApproach']['child'].update(retired=False),
            lambda row: row['paidApproach']['child'].update(stopped=True),
            lambda row: row['paidApproach']['child'].update(performAt=3400),
            lambda row: row['paidApproach']['mutation'].update(bodyUnallocated=False),
            lambda row: row['paidApproach']['observed'].update(bodyUnstarted=False),
            lambda row: row['paidApproach']['mutation'].update(position=dict(x=10, y=20, z=0)),
            lambda row: row['paidApproach']['observed'].update(sameOperation=False),
        ]
        for case, kind in itertools.product(adapter.WALK_CASES, ('sp', 'mp')):
            self.assertEqual(self.verify(self.selection(case, kind, expectation='safe'), self.evidence(case, kind, expectation='safe'))['issues'], [])
            for index, change in enumerate(changes):
                with self.subTest(case=case, kind=kind, index=index):
                    evidence = self.evidence(case, kind, expectation='safe'); change(evidence[0])
                    self.assertTrue(self.verify(self.selection(case, kind, expectation='safe'), evidence)['issues'])

    def test_paid_capture_records_failed_retired_walk_without_claiming_safe_outcome(self):
        evidence = self.evidence('radio-walk-remove', tail=False)
        row = evidence[0]; child = row['paidApproach']['child']
        child.update(performed=False, stopped=True, resultSucceeded=False, atDestination=False)
        child.pop('performAt'); child.pop('finishedAt'); child.pop('arrival')
        row['safeOutcome'] = False
        self.assertEqual(self.verify(self.selection('radio-walk-remove'), evidence)['issues'], [])

    def test_exact_receipt_mutations_are_rejected(self):
        changes = [
            lambda e: e[0]['ids']['old'].update(x=8),
            lambda e: e[0].update(initialQueue=['hold', 'tail', 'setter']),
            lambda e: e[0].update(originalSetterBinding=False),
            lambda e: e[0].update(nativeCallbacksUnchanged=False),
            lambda e: e[0].update(observedAt=2500),
            lambda e: e[0]['observed'].update(oldPresent=True),
            lambda e: e[0]['observed'].update(generatorPresent=False),
            lambda e: e[0]['before']['held'].update(volume=.75),
            lambda e: e[0]['client'].update(heldDataSame=False),
            lambda e: e[0]['client']['books']['tail'].update(id=102),
            lambda e: e[2].update(sameAuthorityData=False),
            lambda e: e[2]['after'].update(liveSameObject=False),
            lambda e: e[2]['after']['held'].update(volume=.75),
            lambda e: e[0]['commands'][0].update(progress=False),
            lambda e: e[0]['commands'][0].update(effectiveDuration=1),
            lambda e: e[0]['commands'][0].update(starts=2),
            lambda e: e[0].update(settleMilliseconds=999),
            lambda e: e[0].update(cleanupSettleMilliseconds=999),
            lambda e: e[4].update(generatorRemoved=False),
            lambda e: e[0].update(cleanupObserved=False),
        ]
        for index, change in enumerate(changes):
            with self.subTest(index=index):
                evidence = self.evidence('tv-move'); change(evidence)
                self.assertTrue(self.verify(self.selection('tv-move'), evidence)['issues'])

    def test_authority_raw_markers_and_completion_cannot_be_omitted(self):
        for kind, marker in itertools.product(('sp', 'mp'), ('PREPARED', 'MUTATED', 'VERIFIED', 'CLEANED')):
            self.assertTrue(self.verify(self.selection(kind=kind), self.evidence(kind=kind), omit=marker)['issues'])
        for completion in ('', '[DEVICE_TARGET_LOSS] COMPLETE_PENDING', '[DEVICE_TARGET_LOSS] COMPLETE\n[DEVICE_TARGET_LOSS] COMPLETE'):
            self.assertTrue(self.verify(self.selection(), self.evidence(), completion=completion)['issues'])

    def test_malformed_nested_receipts_fail_closed(self):
        for field, value in itertools.product(('before', 'mutation', 'observed', 'client', 'server', 'commands', 'acks'), (None, [], 'bad', {})):
            if field == 'acks' and value == []:
                continue
            evidence = self.evidence(); evidence[0][field] = value
            self.assertTrue(self.verify(self.selection(), evidence)['issues'], (field, value))

    def test_lua_mutation_retains_same_authority_object_and_data_without_unsafe_detached_query(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/device-target-loss/shared/QueueDeviceTargetLoss.lua').read_text()
        for case in adapter.ALL_CASES:
            lua = LuaRuntime()
            lua.execute("""
                package.preload.QueueEnergyPlacement=function()return {}end
                now=1000;getTimestampMs=function()return now end
                isServer=function()return true end
                instanceof=function(object,class)return object.class==class end
                local squares={}
                local function square(x,y)
                    local s={x=x,y=y,z=0,objects={}}
                    function s:getX()return self.x end
                    function s:getY()return self.y end
                    function s:getZ()return self.z end
                    function s:getObjects()return {size=function()return #self.objects end,get=function(_,i)return self.objects[i+1]end}end
                    function s:transmitRemoveItemFromSquare(object)
                        removes=removes+1;assert(object.square==self)
                        for i,v in ipairs(self.objects)do if v==object then table.remove(self.objects,i);break end end
                        object.square=nil
                    end
                    function s:AddSpecialObject(object)
                        adds=adds+1;assert(object.square==self);self.objects[#self.objects+1]=object
                    end
                    squares[x..','..y]=s;return s
                end
                old=square(9,20);destination=square(11,20);generatorSquare=square(10,21)
                getCell=function()return {getGridSquare=function(_,x,y,z)assert(z==0);return squares[x..','..y]end}end
                key='device-target-loss:test:100';removes=0;adds=0;transmits=0;powerQueries=0
                object={square=old,class='IsoTelevision',modData={queueDeviceLoss=key}}
                function object:getSquare()return self.square end
                function object:setSquare(s)self.square=s end
                function object:getModData()return self.modData end
                function object:getObjectIndex()return self.square and 0 or -1 end
                function object:transmitCompleteItemToClients()transmits=transmits+1 end
                data={getParent=function()return object end,getDeviceVolume=function()return .5 end,
                    getChannel=function()return 90000 end,getIsTurnedOn=function()return true end,
                    getIsBatteryPowered=function()return false end,hasMedia=function()return false end,
                    getPower=function()return 1 end,canBePoweredHere=function()
                        powerQueries=powerQueries+1;assert(object.square,'unsafe detached query');return true
                    end}
                object.getDeviceData=function()return data end
                old.objects={object}
                generatorSquare.objects={{class='IsoGenerator',getModData=function()return {queueDeviceLoss=key..':generator'}end}}
                local books={}
                for i,name in ipairs({'hold','tail'})do
                    local item={id=i,name=name}
                    function item:getID()return self.id end
                    function item:getFullType()return self.name end
                    function item:getAlreadyReadPages()return 216 end
                    function item:getContainer()return root end
                    books[i]=item
                end
                root={getItemById=function(_,id)return books[id]end,
                    getItems=function()return {size=function()return #books end,get=function(_,i)return books[i+1]end}end}
                player={getInventory=function()return root end,getAlreadyReadPages=function()return 216 end}
                ids={case='tv-remove',key=key,class='IsoTelevision',old={x=9,y=20,z=0},
                    destination={x=11,y=20,z=0},generator={x=10,y=21,z=0},index=0,
                    hold={id=1,type='hold'},tail={id=2,type='tail'}}
                state={authority=true,ids=ids,object=object,data=data,player=player}
            """)
            fixture = lua.execute(source)
            lua.globals().F = fixture
            lua.globals().selected_case = case
            lua.globals().expectedMoved = {'tv-remove': False, 'tv-move': True, 'radio-remove': False, 'radio-move': True,
                'radio-walk-remove': False, 'tv-walk-move': True}[case]
            lua.execute("""
                ids.case=selected_case;object.class=selected_case:sub(1,2)=='tv'and'IsoTelevision'or'IsoRadio';ids.class=object.class
                local originalObject,originalData=object,data
                local receipt=F.mutate(state)
                assert(receipt.sameAuthorityObject and receipt.sameAuthorityData and removes==1)
                assert(state.object==originalObject and state.data==originalData and object:getDeviceData()==originalData)
                local moved=expectedMoved
                assert(receipt.operation==(moved and 'move'or'remove'),'remove/move authority semantics differ')
                assert(receipt.after.oldPresent==false and receipt.after.destinationPresent==moved)
                assert(adds==(moved and 1 or 0)and transmits==(moved and 1 or 0))
                assert(receipt.after.heldDataParentSame and receipt.after.liveSameObject==moved)
                assert(receipt.after.held.volume==.5)
                if not moved then assert(receipt.after.held.powered==false and receipt.after.heldSquare==false)end
                assert(not pcall(F.mutate,state)and removes==1,'authority mutation replay accepted')
            """)

    def test_lua_observes_source_owned_command_functions_without_replacing_them(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/device-target-loss/client/ZZDeviceTargetLoss.lua').read_text()
        functions = 'local function functionSource' + source.split('local function functionSource', 1)[1].split('local function track(', 1)[0]
        operations = (ROOT / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua').read_text()
        command = 'function Operations.command' + operations.split('function Operations.command', 1)[1].split('local commandFactory', 1)[0]
        lua = LuaRuntime()
        lua.execute("""
            local functionBindings={};local commandMarker={};called=0
            local function startCommand()called=called+1 end
            local function waitForCompletion()called=called+1 end
            Operations={};ISQueueActionsAction={new=function(_,character,callback,snapshot)
                return {Type='ISQueueActionsAction',character=character,addActionsFunction=callback,args={snapshot}}
            end}
        """ + command + functions + """
            local callback=function()called=called+1 end
            local action=Operations.command({},callback,{})
            assert(action.start==startCommand and action.waitToStart==waitForCompletion and action.addActionsFunction==callback)
            captureFunctions(action);unchangedFunctions(action,'setter:approach');assert(called==0)
            local original=action.waitToStart
            action.waitToStart=function()called=called+1 end
            local ok,problem=pcall(unchangedFunctions,action,'setter:approach')
            assert(not ok and problem:find('setter:approach',1,true)and problem:find('waitToStart',1,true))
            action.waitToStart=original;unchangedFunctions(action,'setter:approach')
            action.start=nil;assert(not pcall(unchangedFunctions,action,'setter:approach'))
            action.start=startCommand;action.extra=function()called=called+1 end
            assert(not pcall(unchangedFunctions,action,'setter:approach'))
            assert(called==0,'function identity guard invoked a native callback')
        """)

    def test_lua_mutation_requires_owned_exact_binding_before_any_removal(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/device-target-loss/shared/QueueDeviceTargetLoss.lua').read_text()
        for invalid in ('authority', 'object', 'data', 'parent'):
            lua = LuaRuntime()
            lua.execute("""
                package.preload.QueueEnergyPlacement=function()return {}end
                removes=0;instanceof=function()return true end
                object={getModData=function()return {queueDeviceLoss='owned'}end}
                local square={getObjects=function()return {size=function()return 1 end,get=function()return object end}end,
                    transmitRemoveItemFromSquare=function()removes=removes+1 end}
                getCell=function()return {getGridSquare=function()return square end}end
                data={getParent=function()return object end};object.getDeviceData=function()return data end
                state={authority=true,ids={key='owned',class='IsoRadio',old={x=1,y=2,z=0}},object=object,data=data}
            """)
            lua.globals().F = lua.execute(source)
            lua.globals().invalid = invalid
            lua.execute("""
                if invalid=='authority'then state.authority=false
                elseif invalid=='object'then state.object={}
                elseif invalid=='data'then state.data={}
                else data.getParent=function()return {}end end
                assert(not pcall(F.mutate,state)and removes==0,'invalid authority binding reached mutation')
            """)

    def test_lua_prepare_passes_exact_constructor_and_callable_wrapper_arity(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/device-target-loss/shared/QueueDeviceTargetLoss.lua').read_text()
        for case in adapter.ALL_CASES:
            with self.subTest(case=case):
                lua = LuaRuntime()
                lua.execute("""
                    package.preload.QueueEnergyPlacement=function()
                        return {target=function(value)return value end,at=function()return true end}
                    end
                    isServer=function()return false end;getTimestampMs=function()return 1000 end
                    generatorCalls=0;wrapperCalls=0;deviceCalls=0
                    local squares={}
                    cell={getGridSquare=function(_,x,y,z)
                        local key=x..','..y..','..z
                        if not squares[key]then squares[key]={x=x,y=y,z=z,
                            isFree=function()return true end,
                            getFloor=function()return {}end,TreatAsSolidFloor=function()return true end,
                            getRoom=function()return nil end,isVehicleIntersecting=function()return false end,
                            getObjects=function()return {size=function()return 0 end}end,
                            AddSpecialObject=function()end,haveElectricity=function()return true end}end
                        return squares[key]
                    end}
                    getCell=function()return cell end
                    local generatorItem={};instanceItem=function(kind)assert(kind=='Base.Generator');return generatorItem end
                    local sprite={};getSprite=function()return sprite end
                    local function noop()end
                    generator={setCondition=noop,setFuel=noop,setActivated=noop,getModData=function(self)
                        self.modData=self.modData or {};return self.modData end}
                    local function callableWrapper(...)
                        wrapperCalls=wrapperCalls+1;assert(select('#',...)==3,'wrapper received extra bridge argument')
                        local item,world,square=...
                        assert(item==generatorItem and world==cell and square.x==expectedGeneratorX and square.y==21 and square.z==0)
                        return generator
                    end
                    IsoGenerator={new=function(...)
                        generatorCalls=generatorCalls+1;assert(select('#',...)==3,'generator constructor arity differs')
                        return callableWrapper(...)
                    end}
                    local data=setmetatable({hasMedia=function()return false end,canBePoweredHere=function()return true end},
                        {__index=function(_,name)assert(name:sub(1,3)=='set','unexpected DeviceData call '..name);return noop end})
                    device={getDeviceData=function()return data end,getModData=function(self)
                        self.modData=self.modData or {};return self.modData end,getObjectIndex=function()return 1 end}
                    local function deviceConstructor(...)
                        deviceCalls=deviceCalls+1;assert(select('#',...)==3,'device constructor arity differs')
                        local world,square,spr=...
                        assert(world==cell and square.x==expectedDeviceX and square.y==20 and square.z==0 and spr==sprite)
                        return device
                    end
                    IsoTelevision={new=deviceConstructor};IsoRadio={new=deviceConstructor}
                    local nextId=0
                    local root={AddItem=function(_,kind)
                        nextId=nextId+1;local id=nextId
                        return {getNumberOfPages=function()return 220 end,setAlreadyReadPages=noop,getID=function()return id end}
                    end}
                    player={getInventory=function()return root end,setAlreadyReadPages=noop}
                """)
                lua.globals().F = lua.execute(source)
                lua.globals().selectedCase = case
                layout = {'tv-remove': (10, 9), 'tv-move': (10, 9), 'radio-remove': (10, 9),
                          'radio-move': (10, 9), 'radio-walk-remove': (5, 2), 'tv-walk-move': (5, 2)}[case]
                lua.globals().expectedGeneratorX, lua.globals().expectedDeviceX = layout
                lua.execute("""
                    local state=F.prepare(player,selectedCase,'toolkit',{x=10,y=20,z=0},{mode='local'})
                    assert(generatorCalls==1 and wrapperCalls==1 and deviceCalls==1)
                    assert(state.object==device and state.generator==generator)
                """)

    def test_lua_corridor_selection_reads_before_placement_and_never_repairs_tiles(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime()
        lua.execute("""
            chooses=0;reads=0;print=function()end
            package.preload.QueueEnergyPlacement=function()return {
                choose=function()chooses=chooses+1;return {x=10,y=20,z=0}end,target=function(value)return value end}end
            local map={getWorldXMinTiles=function()return 0 end,getWorldYMinTiles=function()return 0 end,
                getWorldXMaxTiles=function()return 64 end,getWorldYMaxTiles=function()return 64 end,
                getWidthInTiles=function()return 64 end}
            getCell=function()return {getChunkMap=function(_,slot)assert(slot==0);return map end,getGridSquare=function(_,x,y,z)
                reads=reads+1
                if x==0 and y==20 then return nil end
                return {getFloor=function()return {}end,TreatAsSolidFloor=function()return true end,
                    getRoom=function()return nil end,isFree=function()return true end,
                    getObjects=function()return {size=function()return 1 end}end,isVehicleIntersecting=function()return false end}
            end}end
        """)
        lua.globals().F = lua.execute((ROOT / 'tests/native_queue/device-target-loss/shared/QueueDeviceTargetLoss.lua').read_text())
        lua.execute("""
            local value=F.choosePlacement({getPlayerNum=function()return 0 end},'radio-walk-remove')
            assert(chooses==1 and reads>36 and value.z==0)
            for dx=-10,1 do for dy=-1,1 do assert(not(value.x+dx==0 and value.y+dy==20))end end
            assert(not F.walkCase('radio-remove')and not F.walkCase('tv-move'))
        """)

    def corridor_lua(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime()
        lua.execute("""
            reads=0;logs={};width=64;unloaded=false;patch={x1=52,x2=63,y1=61,y2=63}
            print=function(value)logs[#logs+1]=value end
            package.preload.QueueEnergyPlacement=function()return {
                choose=function()return {x=10,y=20,z=0}end,target=function(value)return value end}end
            map={getWorldXMinTiles=function()return 0 end,getWorldYMinTiles=function()return 0 end,
                getWorldXMaxTiles=function()return width end,getWorldYMaxTiles=function()return width end,
                getWidthInTiles=function()return width end}
            player={getPlayerNum=function()return 0 end}
            getCell=function()return {getChunkMap=function(_,slot)assert(slot==0);return map end,
                getGridSquare=function(_,x,y,z)
                    assert(x>=0 and x<width and y>=0 and y<width and z==0,'selection queried outside exclusive loaded bounds')
                    reads=reads+1;if unloaded then return nil end
                    return {getFloor=function()return {}end,TreatAsSolidFloor=function()return true end,
                        getRoom=function()return nil end,isFree=function()
                            return x>=patch.x1 and x<=patch.x2 and y>=patch.y1 and y<=patch.y2 end,
                        getObjects=function()return {size=function()return 1 end}end,isVehicleIntersecting=function()return false end}
                end}end
        """)
        lua.globals().F = lua.execute((ROOT / 'tests/native_queue/device-target-loss/shared/QueueDeviceTargetLoss.lua').read_text())
        return lua

    def test_lua_corridor_search_reaches_loaded_edge_beyond_old_radius_without_tile_edits(self):
        lua = self.corridor_lua()
        lua.execute("""
            local selected=F.choosePlacement(player,'tv-walk-move')
            assert(selected.x==62 and selected.y==62 and selected.z==0)
            assert(math.max(math.abs(selected.x-10),math.abs(selected.y-20))>12)
            assert(#logs==1 and logs[1]:find('status=selected',1,true)and logs[1]:find('map=0,0:64,64',1,true))
            local tested=tonumber(logs[1]:match('candidates=(%d+)'));assert(tested>0 and tested<=(64-11)*(64-2))
        """)

    def test_lua_corridor_search_fails_measured_bounded_scan_for_unloaded_squares(self):
        lua = self.corridor_lua()
        lua.execute("""
            unloaded=true
            local ok,problem=pcall(F.choosePlacement,player,'radio-walk-remove')
            local expected=(64-11)*(64-2)
            assert(not ok and reads==expected and #logs==1)
            assert(logs[1]:find('status=failed candidates='..expected,1,true))
            assert(problem:find('No clear loaded native device walking corridor before placement',1,true))
        """)

    def test_lua_corridor_search_rejects_malformed_or_unavailable_native_map_without_fallback(self):
        for mutation in (
            'map=nil', 'map.getWorldXMinTiles=nil', 'map.getWorldXMinTiles=function()return nil end',
            'map.getWorldXMinTiles=function()return .5 end', 'map.getWorldXMaxTiles=function()return width-1 end',
            'width=0', 'width=160', 'map.getWorldXMinTiles=function()return 1000 end',
        ):
            with self.subTest(mutation=mutation):
                lua = self.corridor_lua()
                lua.execute(mutation + ";assert(not pcall(F.choosePlacement,player,'radio-walk-remove')and reads==0)")

    def test_lua_paid_walk_observation_preserves_native_callbacks_tokens_and_lifetime(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/device-target-loss/client/QueueDeviceTargetLossWalk.lua').read_text()
        for mode in ('native', 'toolkit'):
            with self.subTest(mode=mode):
                lua = LuaRuntime()
                lua.execute("""
                    nativeCalls=0
                    ISWalkToTimedAction={Type='ISWalkToTimedAction'};ISWalkToTimedAction.__index=ISWalkToTimedAction
                    function ISWalkToTimedAction:new(player,location)
                        return setmetatable({character=player,location=location,maxTime=-1,stopOnWalk=false,
                            stopOnRun=false,allowedWhileDraggingCorpses=true},self)
                    end
                    function ISWalkToTimedAction:start()nativeCalls=nativeCalls+1 end
                    function ISWalkToTimedAction:update()nativeCalls=nativeCalls+1 end
                    function ISWalkToTimedAction:stop()nativeCalls=nativeCalls+1 end
                    function ISWalkToTimedAction:perform()nativeCalls=nativeCalls+1 end
                    function ISWalkToTimedAction:isValid()nativeCalls=nativeCalls+1 end
                    function ISWalkToTimedAction:isStarted()return self.started==true end
                """, name='@WalkToTimedAction.lua')
                lua.execute("""
                    package.preload['TimedActions/WalkToTimedAction']=function()return ISWalkToTimedAction end
                    getFilenameOfClosure=function(callback)return debug.getinfo(callback,'S').source:gsub('^@','') end
                    clock=1000;getTimestampMs=function()return clock end
                    BehaviorResult={Succeeded='succeeded'}
                    local function square(x,y,z)return {getX=function()return x end,getY=function()return y end,getZ=function()return z end}end
                    origin=square(10,20,0);destination=square(3,20,0);px=10;py=20;pz=0;at=origin;contains=true
                    player={getX=function()return px end,getY=function()return py end,getZ=function()return pz end,
                        getSquare=function()return at end,getCurrentSquare=function()return at end,
                        getCharacterActions=function()return {contains=function()return contains end}end}
                    token={};body={toolkitQueueOperation=token};preparation={toolkitQueueOperation=token}
                    tail={Type='ISReadABook',toolkitQueueOperation={}}
                    child=ISWalkToTimedAction:new(player,destination);child.toolkitQueueOperation=token
                    queue={queue={preparation,child,body,tail},current=preparation,indexOf=function(self,action)
                        for i,value in ipairs(self.queue)do if value==action then return i end end;return -1 end}
                    ISTimedActionQueue={getTimedActionQueue=function()return queue end}
                    getCell=function()return {getGridSquare=function(_,x,y,z)assert(x==3 and y==20 and z==0);return destination end}end
                    tracked={};captures=0;capture=function(action)assert(action==child);captures=captures+1 end
                """)
                lua.globals().W = lua.execute(source)
                lua.globals().mode = mode
                lua.execute("""
                    local bank=W.new({player=player},tracked,capture,mode)
                    if mode=='native'then bank:produced({child,body})
                    else bank:produced({preparation,body});bank:begin(preparation,'perform')end
                    bank:tail(tail)
                    assert(captures==1 and bank.proof.children==1 and nativeCalls==0)
                    queue.queue={child,body,tail};queue.current=child
                    local row=tracked[child];row.started=true;row.starts=1
                    bank:started(child);assert(child.action==nil,'admission observer fabricated native allocation')
                    child.started=true;local native={};child.action=native
                    clock=1100;px=9.8;assert(bank:ready());bank:requestMutation()
                    token.toolkitCancelled=true
                    assert(not pcall(bank.observe,bank),'canceled active walk accepted')
                    token.toolkitCancelled=nil
                    clock=1200;bank:observed();assert(bank.proof.mutation.bodyUnallocated and bank.proof.observed.currentNativeSame)
                    px=3;at=destination;child.result=BehaviorResult.Succeeded
                    clock=1300;bank:begin(child,'perform');row.performed=mode=='toolkit'
                    queue.queue={tail};queue.current=tail;contains=false
                    clock=1400;bank:observe();assert(row.retired and row.resultSucceeded and row.atDestination)
                    assert(bank:safe()==(mode=='toolkit')and child.action==native and child.toolkitQueueOperation==token and nativeCalls==0)
                    token.toolkitCancelled=true
                    if mode=='native'then
                        contains=true
                        assert(not pcall(bank.observe,bank),'canceled queued-retired but Java-live walk accepted')
                        contains=false
                        bank:observe()
                        assert(row.retired and not row.performed and row.finishedAt==nil and not bank:safe(),
                            'native reset after retirement fabricated successful completion')
                    else
                        assert(not pcall(bank.observe,bank),'toolkit canceled retired walk accepted')
                    end
                    token.toolkitCancelled=nil
                    child.toolkitQueueOperation={};assert(not pcall(bank.observe,bank),'replaced walk token accepted')
                    child.toolkitQueueOperation=token;child.action={};assert(not pcall(bank.observe,bank),'replaced native handle accepted')
                    child.action=native;child.additionalTest=function()error('foreign selector invoked')end
                    assert(not pcall(bank.observe,bank)and nativeCalls==0)
                """)


if __name__ == '__main__':
    unittest.main()
