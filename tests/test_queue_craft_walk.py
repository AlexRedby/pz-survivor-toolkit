"""Queue-off pinned craft requires genuine native walking and exact physical returns."""
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
    def selection(self, kind='sp', cases=None):
        return dict(suite='craft', cases=cases or list(craft.EDITOR_OFF_CASES), kind=kind, mode='native',
                    languages=['EN'], mods=list(craft.MODS), clients=1, options={})

    def evidence(self, kind='sp'):
        records = []; raw = []
        for index, case in enumerate(craft.EDITOR_OFF_CASES):
            base = 100 + 20 * index
            tools = [base, base+1]; bags = [base+2, base+3]
            complete = index == 0; blocked = index == 2
            prep = dict(case=case, tools=tools, bags=bags, material=base+4, book=base+5,
                        outputs=0, materialCondition=10, materialUses=0, outputBaseline=[], sparePlanks=[],
                        playerId=42 if kind == 'mp' else -1,
                        toolMeta=[dict(id=id, kind=tool, condition=10, uses=0)
                                  for id, tool in zip(tools, ('Base.Saw', 'Base.HandDrill'))])
            returned = tools[1:] if blocked else tools
            receipt = dict(case=case, materialId=prep['material'], materialPresent=not complete,
                           materialCondition=10, materialUses=0, consumed=int(complete), outputs=int(complete),
                           outputIds=[900] if complete else [], toolsReturned=len(returned), sparePlanks=[], fullOrigin=blocked,
                           resources=[dict(meta, sourceId=bags[i], sourceCount=int(not blocked or i != 0),
                                           rootCount=int(blocked and i == 0)) for i, meta in enumerate(prep['toolMeta'])])
            row = dict({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'}, event='case',
                       id=case, status='passed', producer='CraftChainRecipes.enqueue', queueEnabled=False,
                       toolIds=tools, pickupIds=tools, returnIds=returned, returnStarts=returned,
                       craftProgress=True, tailProgress=complete, tailDiscarded=not complete,
                       nativeStop=not complete, nativeDuration=150, authorityVerified=True,
                       walkDistance=0 if complete else .3, walkProgress=0 if complete else .1,
                       inputReleased=True, blockedToolId=tools[0] if blocked else False)
            records.append(row);raw.extend([('PREPARED', prep), ('WALK_AUTHORITY', receipt)])
        return records, raw

    def verify(self, kind='sp', evidence=None):
        rows, raw = evidence or self.evidence(kind)
        cases = list(craft.EDITOR_OFF_CASES)
        records = [dict(event='setup', cases=cases, expected=3, queueEnabled=False, nativeDurations=True), *rows,
                   dict(event='complete', cases=cases, expected=3, performed=3, failed=0, skipped=0)]
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(dict(row, suite='craft', kind=kind, mode='native', actor='client1'))
                         for row in records)
        authority = '\n'.join('[CRAFT_QUEUE_TEST] ' + marker + ' ' + json.dumps(row) for marker, row in raw)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'client1-launch.log').write_text(text + ('\n' + authority if kind == 'sp' else ''))
            if kind == 'mp':
                (root / 'server-launch.log').write_text(authority)
            return craft.verify(root, self.selection(kind), {})

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
        gate = source[source.index('   if walk and walk.released then'):source.index("   assert(current and progress")]
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
