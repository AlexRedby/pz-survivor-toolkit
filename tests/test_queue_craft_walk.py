"""Pinned craft requires genuine native walking and exact physical returns."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import craft, craft_walk


class CraftWalkTests(unittest.TestCase):
    def selection(self, kind='sp', cases=None, enabled=False):
        return dict(suite='craft', cases=cases or list(craft.EDITOR_ON_WALK_CASES if enabled else craft.EDITOR_OFF_CASES),
                    kind=kind, mode='toolkit' if enabled else 'native',
                    languages=['EN'], mods=list(craft.MODS), clients=1, options={})

    def evidence(self, kind='sp', enabled=False):
        records = []; raw = []
        for index, case in enumerate(craft.EDITOR_ON_WALK_CASES if enabled else craft.EDITOR_OFF_CASES):
            base = 100 + 20 * index
            tools = [base, base+1]; bags = [base+2, base+3]
            running = case == craft.RUN_PICKUP_CASE
            complete = case == 'complete-pinned-tools'; blocked = case == 'walk-pinned-full'
            kept = case == 'walk-editor-keep-saw'; retained = blocked or kept
            prep = dict(case=case, tools=tools, bags=bags, material=base+4, book=base+5,
                        outputs=0, materialCondition=10, materialUses=0, outputBaseline=[], sparePlanks=[],
                        playerId=42 if kind == 'mp' else -1,
                        toolMeta=[dict(id=id, kind=tool, condition=10, uses=0)
                                  for id, tool in zip(tools, ('Base.Saw', 'Base.HandDrill'))])
            returned = tools[1:] if retained else tools
            receipt = dict(case=case, materialId=prep['material'], materialPresent=not complete,
                           materialCondition=10, materialUses=0, consumed=int(complete), outputs=int(complete),
                           outputIds=[900] if complete else [], toolsReturned=len(returned), sparePlanks=[], fullOrigin=blocked,
                           resources=[dict(meta, sourceId=bags[i], sourceCount=int(not retained or i != 0),
                                           rootCount=int(retained and i == 0)) for i, meta in enumerate(prep['toolMeta'])])
            row = dict({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'}, event='case',
                       id=case, status='passed', producer='CraftChainRecipes.enqueue', queueEnabled=enabled,
                       toolIds=tools, pickupIds=tools, returnIds=returned, returnStarts=returned,
                       craftProgress=not running, tailProgress=complete, tailDiscarded=not complete,
                       nativeStop=not complete, nativeDuration=150, authorityVerified=True,
                       walkDistance=0 if complete else .3, walkProgress=0 if complete else .1,
                       inputReleased=True, blockedToolId=tools[0] if blocked else False)
            if enabled:
                row.update(instantActions=False, pauseOnFocusLoss=False, craftChainsEnabled=True, foreignReturnProvider=False,
                           eventTrace=['pickup-saw', 'pickup-drill', 'craft-progress'] + (['keep-saw'] if kept else []) +
                                      ['walk-input', 'native-stop'] + (['return-drill'] if kept else ['return-saw', 'return-drill']))
                if running:
                    row.update(runObserved=True, pickup=dict(itemId=tools[1], sourceId=bags[1], firstId=tools[0],
                               firstConfirmed=True, sourcePresent=True, rootPresent=False, started=True, craftStarted=False,
                               stopOnRun=True, progress=.1, duration=50, transaction=7 if kind=='mp' else 0,
                               watchEnrolled=kind=='mp',
                               done=False, rejected=False, stopEntry=dict(transaction=7 if kind=='mp' else 0,
                               done=False, rejected=False, current=True, sourcePresent=True, rootPresent=False),
                               stopTransaction=0, stopDone=False, stopRejected=False, finalTransaction=0,
                               finalDone=False, finalRejected=False),
                               eventTrace=['pickup-saw', 'pickup-drill', 'drill-progress', 'run-input', 'native-stop',
                                           'return-saw', 'return-drill'])
                if kept:
                    row.update(keptId=tools[0], keptSourceId=bags[0], siblingId=tools[1], siblingSourceId=bags[1],
                               keepSucceeded=True, keptRowPending=True, keptRowRemoved=True, siblingPreserved=True,
                               craftPreservedAfterKeep=True, keepProgress=.1)
            records.append(row);raw.extend([('PREPARED', prep), ('WALK_AUTHORITY', receipt)])
        return records, raw

    def verify(self, kind='sp', evidence=None, enabled=False):
        rows, raw = evidence or self.evidence(kind, enabled)
        selection = self.selection(kind, enabled=enabled); cases = selection['cases']
        records = [dict(event='setup', cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True), *rows,
                   dict(event='complete', cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0)]
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(dict(row, suite='craft', kind=kind, mode=selection['mode'], actor='client1'))
                         for row in records)
        authority = '\n'.join('[CRAFT_QUEUE_TEST] ' + marker + ' ' + json.dumps(row) for marker, row in raw)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'client1-launch.log').write_text(text + ('\n' + authority if kind == 'sp' else ''))
            if kind == 'mp':
                (root / 'server-launch.log').write_text(authority)
            return craft.verify(root, selection, {})

    def test_registered_isolated_native_sp_and_host(self):
        for kind in ('sp', 'mp'):
            craft.validate(self.selection(kind))
            self.assertEqual([], self.verify(kind)['issues'])
        registered = {row['id']: row for row in craft.definitions()['craft']['cases']}
        for case in craft.EDITOR_OFF_CASES:
            self.assertEqual(['native'], registered[case]['modes'])
        for change in ({'mode': 'toolkit'}, {'cases': ['borrowed-tools', *craft.EDITOR_OFF_CASES]},
                       {'mods': craft.MODS + ['P4TidyUpMeister']}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                craft.validate(dict(self.selection(), **change))

    def test_early_movement_engine_stop_and_released_input_required(self):
        for key, value in [('walkDistance', 0), ('walkDistance', True), ('walkDistance', float('nan')),
                           ('walkProgress', 0), ('walkProgress', .3), ('nativeStop', False),
                           ('nativeStop', 1), ('inputReleased', False), ('tailDiscarded', False),
                           ('tailProgress', True), ('queueEnabled', True), ('producer', 'forceStop')]:
            evidence = self.evidence();evidence[0][1][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence=evidence)['issues'])

    def test_actual_return_progress_matches_exact_source_effect(self):
        for key, value in [('pickupIds', [120]), ('returnIds', [120]), ('returnStarts', [120]),
                           ('returnStarts', [120, 120, 121]), ('toolIds', [120, 122])]:
            evidence = self.evidence();evidence[0][1][key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify(evidence=evidence)['issues'])
        for mutation in ('wrong-source', 'changed-tool', 'duplicate-tool', 'blocked-sibling', 'blocked-return', 'authority-only'):
            rows, raw = self.evidence(); receipt = raw[-1][1]
            if mutation == 'wrong-source': receipt['resources'][1]['sourceId'] = receipt['resources'][0]['sourceId']
            elif mutation == 'changed-tool': receipt['resources'][1]['condition'] -= 1
            elif mutation == 'duplicate-tool': receipt['resources'][0]['sourceCount'] = 1
            elif mutation == 'blocked-sibling': receipt['resources'][1].update(sourceCount=0, rootCount=1)
            elif mutation == 'blocked-return': rows[-1]['returnStarts'] = rows[-1]['toolIds']
            else: receipt['toolsReturned'] = 2
            if mutation != 'authority-only': rows[-1].update({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'})
            with self.subTest(mutation=mutation):
                self.assertTrue(self.verify(evidence=(rows, raw))['issues'])

    def test_unchanged_input_on_stop_and_real_consumption_on_completion(self):
        for index, key, value in [(0, 'consumed', 0), (0, 'outputs', 0), (0, 'outputIds', [100]),
                                  (0, 'nativeStop', True), (1, 'consumed', 1), (1, 'outputs', 1),
                                  (1, 'materialPresent', False), (2, 'fullOrigin', False), (2, 'blockedToolId', 141)]:
            rows, raw = self.evidence();rows[index][key] = value
            if key in raw[2*index+1][1]:raw[2*index+1][1][key] = value
            with self.subTest(index=index, key=key):
                self.assertTrue(self.verify(evidence=(rows, raw))['issues'])

    def test_authority_order_uniqueness_and_cross_case_ids_required(self):
        for mutation in ('missing', 'duplicate', 'reordered', 'cross-case-id'):
            rows, raw = self.evidence()
            if mutation == 'missing':raw.pop()
            elif mutation == 'duplicate':raw.append(raw[-1])
            elif mutation == 'reordered':raw[0], raw[1] = raw[1], raw[0]
            else:raw[2][1]['bags'][0] = raw[0][1]['bags'][0]
            with self.subTest(mutation=mutation):
                self.assertTrue(self.verify('mp', (rows, raw))['issues'])

    def test_fixture_cannot_settle_with_idle_accumulated_during_walking(self):
        from lupa import LuaRuntime
        source = (ROOT / 'tests/native_queue/craft/shared/QueueCraftWalk.lua').read_text()
        helpers = source[source.index('local function returnsFinished()'):source.index('local function chooseDirection(player)')]
        gate = source[source.index('   if walk and walk.released then'):source.index("   assert(current and(progress")]
        lua = LuaRuntime()
        lua.execute("""
            local clock=1000
            getTimestampMs=function()return clock end
            local ids={tools={101,102}}
            local first,second={},{}
            local root={};local bags={first,second}
            local items={}
            for i,id in ipairs(ids.tools)do
                items[id]={container=root,getContainer=function(self)return self.container end}
            end
            root.getItemById=function(self,id)return items[id]end
            local state={root=root,bags={}}
            for i,bag in ipairs(bags)do
                state.bags[i]={getItemContainer=function()return bag end}
            end
            local starts,returned={},{}
            local selected='walk-pinned-tools'
            local function case()return selected end
            local function running()return false end
            local queue={queue={}}
            local function q()return queue end
            local moving=true
            local player={hasTimedActions=function()return false end,isPlayerMoving=function()return moving end}
            local idle=27
            local walk={released=true,releasedAt=1000}
            local settledSince
        """ + helpers + """
            local accepted=false
            local function gate()
        """ + gate + """
                accepted=true
            end
            gate();assert(not accepted,'idle during movement paid settlement')
            moving=false;gate();assert(not accepted,'missing actual returns paid settlement')
            starts={101,102};returned={[101]=true,[102]=true}
            items[101].container=first;items[102].container=second
            gate();assert(not accepted,'completed returns skipped quiet interval')
            clock=1250;gate();assert(accepted,'stationary finished returns did not settle')
            starts={101,101,102}
            assert(not pcall(returnsFinished),'duplicate native return was hidden')
            starts={102};returned={[102]=true};selected='walk-pinned-full'
            items[101].container=root
            assert(returnsFinished(),'blocked tool root plus sibling return did not settle')
            starts={101,102};returned[101]=true
            assert(not pcall(returnsFinished),'blocked source accepted forbidden return')
            selected='walk-editor-keep-saw';starts={102};returned={[102]=true}
            assert(returnsFinished(),'explicit Keep saw plus completed drill return did not settle')
            starts={101,102};returned[101]=true
            assert(not pcall(returnsFinished),'waived saw return was resurrected')
        """)

    def test_editor_on_native_walk_and_exact_saw_keep_sp_host(self):
        for kind in ('sp', 'mp'):
            craft.validate(self.selection(kind, enabled=True))
            self.assertEqual([], self.verify(kind, enabled=True)['issues'])
        registered = {row['id']: row for row in craft.definitions()['craft']['cases']}
        for case in craft.EDITOR_ON_WALK_CASES:
            self.assertEqual(['toolkit'], registered[case]['modes'])
        for change in ({'mode': 'native'}, {'cases': craft.WALK_CASES},
                       {'cases': [craft.KEEP_CASE, *craft.EDITOR_ON_WALK_CASES]},
                       {'mods': craft.MODS + ['P4TidyUpMeister']}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                craft.validate(dict(self.selection(enabled=True), **change))

    def test_editor_on_exact_pending_keep_and_native_controls_required(self):
        for key, value in [('keptId', 121), ('keptSourceId', 123), ('siblingId', 120), ('siblingSourceId', 122),
                           ('keepSucceeded', False), ('keptRowPending', False), ('keptRowRemoved', False),
                           ('siblingPreserved', False), ('craftPreservedAfterKeep', False), ('keepProgress', 0),
                           ('keepProgress', .2), ('walkProgress', 'invalid'), ('instantActions', True),
                           ('pauseOnFocusLoss', True), ('craftChainsEnabled', False), ('foreignReturnProvider', True),
                           ('nativeStop', False), ('walkDistance', 0), ('queueEnabled', False),
                           ('returnStarts', [120, 121]), ('returnIds', [120, 121]), ('pickupIds', [121])]:
            evidence = self.evidence(enabled=True); evidence[0][1][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence=evidence, enabled=True)['issues'])

    def test_editor_on_causal_order_and_no_unearned_return_required(self):
        for mutation in ('missing-keep', 'duplicate-stop', 'walk-before-keep', 'return-before-stop',
                         'craft-before-pickup', 'saw-return', 'wrong-shape'):
            evidence = self.evidence(enabled=True); trace = evidence[0][1]['eventTrace']
            if mutation == 'missing-keep': trace.remove('keep-saw')
            elif mutation == 'duplicate-stop': trace.append('native-stop')
            elif mutation == 'walk-before-keep': trace[3], trace[4] = trace[4], trace[3]
            elif mutation == 'return-before-stop': trace[-1], trace[-2] = trace[-2], trace[-1]
            elif mutation == 'craft-before-pickup': trace[0], trace[2] = trace[2], trace[0]
            elif mutation == 'saw-return': trace.append('return-saw')
            else: trace[0] = 1
            with self.subTest(mutation=mutation):
                self.assertTrue(self.verify(evidence=evidence, enabled=True)['issues'])

    def test_editor_on_server_endpoints_and_intact_material_are_required(self):
        for mutation in ('saw-returned', 'drill-root', 'wrong-origin', 'changed-saw', 'changed-material',
                         'consumed', 'output', 'authority-only'):
            rows, raw = self.evidence('mp', enabled=True); receipt = raw[3][1]
            if mutation == 'saw-returned': receipt['resources'][0].update(sourceCount=1, rootCount=0)
            elif mutation == 'drill-root': receipt['resources'][1].update(sourceCount=0, rootCount=1)
            elif mutation == 'wrong-origin': receipt['resources'][1]['sourceId'] = receipt['resources'][0]['sourceId']
            elif mutation == 'changed-saw': receipt['resources'][0]['condition'] = 9
            elif mutation == 'changed-material': receipt['materialCondition'] = 9
            elif mutation == 'consumed': receipt.update(consumed=1, materialPresent=False)
            elif mutation == 'output': receipt.update(outputs=1, outputIds=[900])
            else: receipt['toolsReturned'] = 2
            if mutation != 'authority-only':
                rows[1].update({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'})
            with self.subTest(mutation=mutation):
                self.assertTrue(self.verify('mp', (rows, raw), enabled=True)['issues'])


    def test_run_during_second_pickup_requires_genuine_inflight_and_unchanged_authority(self):
        for kind in ('sp', 'mp'):
            self.assertEqual([], self.verify(kind, enabled=True)['issues'])
        for key, value in [('firstConfirmed', False), ('sourcePresent', False), ('rootPresent', True),
                           ('started', False), ('craftStarted', True), ('progress', 0), ('duration', 0),
                           ('itemId', 1), ('sourceId', 1), ('transaction', 0), ('done', True), ('rejected', True),
                           ('watchEnrolled', False), ('watchEnrolled', None), ('watchEnrolled', 1)]:
            evidence = self.evidence('mp', enabled=True); evidence[0][-1]['pickup'][key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify('mp', evidence, enabled=True)['issues'])
        for key, value in [('runObserved', False), ('craftProgress', True), ('returnStarts', []),
                           ('eventTrace', ['run-input', 'native-stop'])]:
            evidence = self.evidence('mp', enabled=True); evidence[0][-1][key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify('mp', evidence, enabled=True)['issues'])
        for mutation in ('drill-root', 'saw-root', 'material-changed', 'output'):
            rows, raw = self.evidence('mp', enabled=True); receipt = raw[-1][1]
            if mutation == 'drill-root': receipt['resources'][1].update(sourceCount=0, rootCount=1)
            elif mutation == 'saw-root': receipt['resources'][0].update(sourceCount=0, rootCount=1)
            elif mutation == 'material-changed': receipt['materialCondition'] = 9
            else: receipt.update(outputs=1, outputIds=[900])
            rows[-1].update({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'})
            with self.subTest(mutation=mutation):
                self.assertTrue(self.verify('mp', (rows, raw), enabled=True)['issues'])
        rows, raw = self.evidence('mp', enabled=True)
        rows[-1].update(returnIds=[rows[-1]['toolIds'][0]], returnStarts=[rows[-1]['toolIds'][0]])
        rows[-1]['eventTrace'].remove('return-drill')
        self.assertEqual([], self.verify('mp', (rows, raw), enabled=True)['issues'])

    def test_host_pickup_watch_forwarder_preserves_result_and_restores_optional_global(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/craft/shared/QueueCraftWalk.lua').read_text()
        helpers = source[source.index('local function restorePickupWatch()'):source.index('local function keeping()')]
        LuaRuntime().execute("""
            local config={kind='mp'}
            local pickupEvidence={}
            local originalPickupWatch,pickupWatchForwarder
        """ + helpers + """
            local owned,foreign,receipt={},{},{}
            local calls={}
            local original=function(action)calls[#calls+1]=action;return receipt end
            pzWatchInterruptedPickup=original
            observePickupWatch(owned)
            assert(pzWatchInterruptedPickup~=original and pickupEvidence.watchEnrolled==false)
            assert(pzWatchInterruptedPickup(foreign)==receipt and pickupEvidence.watchEnrolled==false)
            assert(pzWatchInterruptedPickup(owned)==receipt and pickupEvidence.watchEnrolled==true)
            assert(calls[1]==foreign and calls[2]==owned)
            restorePickupWatch();assert(pzWatchInterruptedPickup==original)
            pzWatchInterruptedPickup=function()return nil end
            local refusing=pzWatchInterruptedPickup
            observePickupWatch(owned)
            assert(pzWatchInterruptedPickup(owned)==nil and pickupEvidence.watchEnrolled==false)
            restorePickupWatch();assert(pzWatchInterruptedPickup==refusing)
            pzWatchInterruptedPickup=nil
            observePickupWatch(owned)
            assert(pzWatchInterruptedPickup==nil and pickupEvidence.watchEnrolled==false)
            restorePickupWatch();assert(pzWatchInterruptedPickup==nil)
            config.kind='sp';pzWatchInterruptedPickup=original;pickupEvidence={}
            observePickupWatch(owned)
            assert(pzWatchInterruptedPickup==original and pickupEvidence.watchEnrolled==nil)
        """)

    def test_staging_builds_only_disposable_input_mod_and_tracks_its_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory);runtime = {'roles': {'client1': {'cache': str(output / 'client1')},
                                                         'server': {'cache': str(output / 'server')}}}
            def compile(command, **kwargs):
                classes = Path(command[command.index('-d')+1]); target = classes / 'toolkit/craftwalk/Main.class'
                target.parent.mkdir(parents=True); target.write_bytes(b'compiled')
            with patch.object(craft_walk.preparation_process, 'run', side_effect=compile):
                craft.stage(ROOT, output, Path('/game'), Path('/jdk'), self.selection('mp'), {}, runtime)
            self.assertEqual(['CraftWalkInput'], runtime['fixture']['mods'])
            for role in runtime['roles'].values():
                layer = Path(role['cache']) / 'mods/CraftWalkInput/42'
                self.assertTrue((layer / 'media/java/CraftWalkInput.jar').is_file())
                self.assertIn('javaPkgName=toolkit.craftwalk', (layer / 'mod.info').read_text())
            self.assertIn(ROOT / 'tests/native_queue/craft/java/Main.java', craft.sources(ROOT, self.selection()))


if __name__ == '__main__':
    unittest.main()
