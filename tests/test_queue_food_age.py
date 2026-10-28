"""Natural-age receipts require actual row, clock, event and cleanup evidence."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import auxiliary
INTAKE = ROOT / 'tests/native_queue/contributions/storage-profile'
V = auxiliary._load(INTAKE / 'food_age_verify.py')


def receipts():
    result = [('AGE_SETUP', dict(native=True, foodType='Base.Apple', phases=4, kind='sp', naturalAgeing=True,
                                ageControl='phase-setup-only', physicalInput=False, network=False, timing=False))]
    for index, (size, mode) in enumerate(((199, 'clean'), (200, 'clean'), (199, 'vanilla'), (200, 'vanilla')), 1):
        result.append(('AGE_PHASE', dict(index=index, size=size, mode=mode,
            paneClass='CleanUI_' + ('Clean' if mode == 'clean' else 'Vanilla') + '_ISInventoryPane', native=True,
            optimized=mode == 'clean' and size == 200, headId=index * 1000, tailId=index * 1000 + size,
            ageBefore=4.996, ageAfter=5.001, worldBefore=100, worldAfter=100.15, eventWorld=100.12,
            events=1, headFresh=True, tailFresh=False, headGroup=size-1, tailGroup=1,
            separatePublishedRows=True, identities=True, visibleObservation=True, hiddenReopen=True,
            primaryPasses=100, naturalAgeing=True, observationAgeWrites=0, elapsedMs=15000)))
    result.append(('AGE_RESTORED', dict(ownedRemoved=798, originalItems=5, observers=True, items=True,
                                       mode=True, optimize=True, phases=4)))
    return result


def log(rows):
    return '\n'.join('[STORAGE_PROFILE] ' + kind + ' ' + json.dumps(row) for kind, row in rows) + '\n[STORAGE_PROFILE] COMPLETE\n'


class NativeFoodAgeQueueTests(unittest.TestCase):
    def test_complete_natural_expiry_evidence(self):
        self.assertEqual(len(V.verify(ROOT, log(receipts()))['food_age']), 4)

    def test_missing_failed_or_contradictory_evidence_fails_closed(self):
        good = receipts()
        mutations = [(0, 'naturalAgeing', False), (0, 'network', True), (0, 'ageControl', 'observed-setAge'),
            (1, 'events', 0), (1, 'events', 2), (1, 'ageBefore', 5), (1, 'ageAfter', 4.999),
            (1, 'headId', 1199), (1, 'worldAfter', 100), (1, 'eventWorld', 100), (1, 'eventWorld', 200),
            (1, 'tailGroup', 199), (1, 'headGroup', 199), (1, 'headFresh', False), (1, 'identities', False),
            (1, 'separatePublishedRows', False), (1, 'hiddenReopen', False), (1, 'visibleObservation', False),
            (1, 'observationAgeWrites', 1), (1, 'primaryPasses', 0), (1, 'elapsedMs', 45000),
            (2, 'optimized', False), (3, 'mode', 'clean'), (4, 'optimized', True),
            (5, 'ownedRemoved', 799), (5, 'observers', False), (5, 'optimize', False)]
        for index, key, value in mutations:
            changed = copy.deepcopy(good); changed[index][1][key] = value
            with self.subTest(index=index, key=key), self.assertRaises(ValueError):
                V.verify(ROOT, log(changed))
        for changed in (good[1:], good[:-1], good + [good[-1]], good[:1] + list(reversed(good[1:]))):
            with self.assertRaises(ValueError): V.verify(ROOT, log(changed))
        for extra in ('[STORAGE_PROFILE] FAIL {}', 'KahluaException', '[STORAGE_PROFILE] COMPLETE'):
            with self.assertRaises(ValueError): V.verify(ROOT, log(good) + extra)

    def test_malformed_receipts_cannot_hide_behind_logger_prefix(self):
        good = '\n'.join('LOG : Lua > ' + line for line in log(receipts()).splitlines())
        self.assertEqual(len(V.verify(ROOT, good)['food_age']), 4)
        for extra in ('AGE_UNKNOWN {}', 'AGE_PHASE', 'AGE_PHASE null', 'AGE_PHASE []', 'AGE_PHASE {broken}',
                      'AGE_PHASE {"index":1,"index":2}', 'AGE_PHASE {"ageAfter":NaN}',
                      'AGE_PHASE ' + ' ' * 16384 + '{}'):
            with self.subTest(extra=extra[:70]), self.assertRaises(ValueError):
                V.verify(ROOT, good + '\nLOG : Lua > [STORAGE_PROFILE] ' + extra)

    def test_sp_effect_registration_and_private_stage(self):
        case = next(row for row in auxiliary.definitions()['storage-profile']['cases'] if row['id'] == 'inventory-food-age')
        self.assertEqual(case['capability'], 'effect'); self.assertEqual(case['kinds'], ['sp'])
        selection = dict(suite='storage-profile', kind='sp', mode='toolkit', cases=['inventory-food-age'],
                         languages=['EN'], mods=list(auxiliary.INVENTORY_MODS), options={})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); cache = root / 'client1'; cache.mkdir()
            auxiliary.stage(ROOT, root, root / 'game', root / 'jdk', selection,
                            {'PZSurvivorToolkit': ROOT / 'PZSurvivorToolkit'},
                            {'roles': {'client1': {'cache': str(cache)}}})
            client = cache / 'mods/StorageProfileNative/42/media/lua/client'
            self.assertEqual({path.name for path in client.iterdir()}, {'ZZFoodAgeNative.lua'})
            self.assertEqual((client / 'ZZFoodAgeNative.lua').read_bytes(), (INTAKE / 'ZZFoodAgeNative.lua').read_bytes())
            (cache / 'console.txt').write_text(log(receipts()))
            result = auxiliary.verify(root, selection, {})
            self.assertFalse(result['issues']); self.assertEqual(result['outcomes'][0]['status'], 'passed')
            (cache / 'console.txt').write_text(log(receipts()) + '[STORAGE_PROFILE] FAIL {}')
            self.assertEqual(auxiliary.verify(root, selection, {})['outcomes'][0]['status'], 'failed')
        with self.assertRaises(ValueError): auxiliary.validate(dict(selection, kind='mp'))

    def test_passive_observer_preserves_returns_failure_and_actual_rows(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime()
        lua.execute('''
          require=function()return {cases={'inventory-food-age'}}end
          Events={};for _,name in ipairs({'OnTick','OnMainMenuEnter','OnGameStart','OnPreUIDraw','OnContainerUpdate'})do
            Events[name]={Add=function(callback)Events[name].callback=callback end,Remove=function()end}
          end
        ''')
        source = (INTAKE / 'ZZFoodAgeNative.lua').read_text()
        # The fixture has one setup-only age write, and no direct age refresh.
        self.assertEqual(source.count(':setAge('), 1); self.assertNotIn(':updateAge(', source)
        fixture = lua.execute(source + '''
          return {observe=observe,restore=restoreObserver,rows=rows,
           seed=function(testPane,testFoods)
             pane=testPane;foods=testFoods;foodSet={};for _,item in ipairs(foods)do foodSet[item]=true end
             head=foods[1];tail=foods[#foods];passes=0;published=nil;observerFailure=nil
           end,failed=function()return observerFailure end}
        ''')
        lua.execute('''
          local fixture=...
          local head,tail={},{}
          local rows={{items={head,head,tail}}}
          local fault,calls={},0
          local pane={items={},renderdetails=function(self,dragged)
            calls=calls+1;if calls==1 then error(fault,0)end
            if not dragged then self.items=rows end
            return 'native',nil,'tail'
          end}
          local original=pane.renderdetails
          fixture.seed(pane,{head,tail});fixture.observe()
          assert(fixture.rows()==nil,'unpublished rows accepted')
          local ok,err=pcall(pane.renderdetails,pane,false)
          assert(not ok and err==fault and fixture.failed()==fault)
          pane:renderdetails(true);assert(fixture.rows()==nil,'dragged pass published rows')
          local a,b,c=pane:renderdetails(false)
          assert(a=='native'and b==nil and c=='tail'and fixture.failed()==fault)
          local current=fixture.rows();assert(current.headRow==1 and current.tailGroup==2)
          rows[1].items={head,head};rows[2]={items={tail,tail}}
          current=fixture.rows();assert(current.headRow==1 and current.tailRow==2 and current.tailGroup==1)
          rows[2].items={tail,tail,tail};assert(not pcall(fixture.rows),'duplicate actual item accepted')
          fixture.restore();assert(pane.renderdetails==original)
          fixture.observe();local foreign=function()end;pane.renderdetails=foreign
          assert(not pcall(fixture.restore)and pane.renderdetails==foreign,'foreign observer overwritten')
        ''', fixture)


if __name__ == '__main__': unittest.main()
