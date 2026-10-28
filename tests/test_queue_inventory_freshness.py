"""Functional freshness native gate must reject incomplete or broadened claims."""
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
V = auxiliary._load(INTAKE / 'freshness_verify.py')


def receipts(active='clean'):
    rows = [('FRESH_SETUP', dict(native=True, foodType='Base.Apple', food=6, spacers=45, phases=19,
        activeMode=active, physicalInput=False, pixelCoverage=False, timing=False,
        naturalAgeing=False, ageControl='fixture-only-restored'))]
    other = 'vanilla' if active == 'clean' else 'clean'
    specs = [(mode, view) for mode in (active, other) for view in V.VIEWS] + [(active, 'hover')]
    for index, (mode, view) in enumerate(specs, 1):
        enabled = mode == active and view not in ('disabled', 'hidden')
        food = int(enabled and view != 'offscreen')
        bar, percentage = view not in ('percentage-only', 'disabled'), view not in ('bar-only', 'disabled')
        texts = food if view in ('hover', 'expanded', 'partial', 'percentage-only') else 0
        rows.append(('FRESH_PHASE', dict(index=index, mode=mode, view=view, native=True,
            paneClass='CleanUI_' + ('Clean' if mode == 'clean' else 'Vanilla') + '_ISInventoryPane',
            active=mode == active, fixtureChildren=6 if view in ('expanded', 'partial') else 0, pageVisible=view != 'hidden', paneVisible=True, rows=50,
            separators=int(mode == 'clean'), visibleSeparators=int(mode == 'clean' and view != 'hidden'), visibleRows=10 if enabled else 0, foodRows=food,
            visits=12 if enabled else 0, hiddenVisits=0, rects=4 * food * bar + texts, texts=texts,
            exactOutput=True, currentRows=True, primaryPublished=True, items=True, options=True, tailWorst=True,
            fixtureAgeRestored=True, bar=bar, percentage=percentage, draggedNative=True,
            draggedPresenterCalls=0, primary=view != 'hidden', directHidden=view == 'hidden',
            layout=True, layoutReserved=mode == active and percentage)))
    rows.append(('FRESH_RESTORED', dict(ownedRemoved=51, foodRemoved=6, originalItems=4, observers=True,
        items=True, options=True, mode=True, fixtureAges=True, phases=19)))
    return rows


def log(rows):
    return '\n'.join('[STORAGE_PROFILE] ' + kind + ' ' + json.dumps(row) for kind, row in rows) + '\n[STORAGE_PROFILE] COMPLETE\n'


class InventoryFreshnessTests(unittest.TestCase):
    def test_initial_owner_and_repeated_toggle_evidence(self):
        for active in ('clean', 'vanilla'):
            self.assertEqual(len(V.verify(ROOT, log(receipts(active)))['freshness']), 19)

    def test_incomplete_or_mutated_receipts_fail_closed(self):
        good = receipts()
        mutations = [(0, 'timing', True), (0, 'naturalAgeing', True), (0, 'phases', 18),
            (1, 'primaryPublished', False), (1, 'exactOutput', False), (1, 'currentRows', False), (1, 'hiddenVisits', 1),
            (1, 'texts', 1), (2, 'texts', 0), (3, 'foodRows', 0), (4, 'fixtureAgeRestored', False),
            (6, 'percentage', True), (7, 'bar', True), (8, 'visits', 1), (9, 'pageVisible', True),
            (10, 'visits', 1), (10, 'active', True), (10, 'layoutReserved', True),
            (19, 'draggedPresenterCalls', 1), (19, 'layout', False), (20, 'observers', False),
            (20, 'ownedRemoved', 50), (20, 'options', False)]
        for index, key, value in mutations:
            changed = copy.deepcopy(good); changed[index][1][key] = value
            with self.subTest(index=index, key=key), self.assertRaises(ValueError):
                V.verify(ROOT, log(changed))
        for changed in (good[1:], good[:-1], good + [good[-1]], good[:2] + list(reversed(good[2:]))):
            with self.assertRaises(ValueError): V.verify(ROOT, log(changed))
        for extra in ('[STORAGE_PROFILE] FAIL test\n', '[STORAGE_PROFILE] COMPLETE\n', 'KahluaException\n'):
            with self.assertRaises(ValueError): V.verify(ROOT, log(good) + extra)
        changed = copy.deepcopy(good)
        for kind, row in changed:
            if kind == 'FRESH_PHASE': row['separators'] = 0
        with self.assertRaises(ValueError): V.verify(ROOT, log(changed))

    def test_malformed_unknown_and_non_object_receipts_fail_closed(self):
        good = log(receipts())
        for extra in (
            '[STORAGE_PROFILE] FRESH_PHASE {broken json}',
            '[STORAGE_PROFILE] FRESH_UNKNOWN {}',
            '[STORAGE_PROFILE] FRESH_PHASE',
            '[STORAGE_PROFILE] FRESH_PHASE null',
            '[STORAGE_PROFILE] FRESH_PHASE []',
            '[STORAGE_PROFILE] FRESH_PHASE {"index": 1, "index": 2}',
            '[STORAGE_PROFILE] FRESH_PHASE {"index": NaN}',
            '[STORAGE_PROFILE] FRESH_PHASE ' + ' ' * 16384 + '{}',
        ):
            with self.subTest(extra=extra[:80]), self.assertRaises(ValueError):
                V.verify(ROOT, good + extra + '\n')
        # Native logger prefixes are allowed; malformed receipts still cannot hide.
        prefixed = '\n'.join('LOG : Lua > ' + line for line in good.splitlines())
        self.assertEqual(len(V.verify(ROOT, prefixed)['freshness']), 19)
        with self.assertRaises(ValueError):
            V.verify(ROOT, prefixed + '\nLOG : Lua > [STORAGE_PROFILE] FRESH_OTHER {}\n')

    def test_functional_registration_staging_and_adapter(self):
        spec = next(row for row in auxiliary.definitions()['storage-profile']['cases'] if row['id'] == 'inventory-freshness')
        self.assertEqual(spec['capability'], 'effect')
        selection = dict(suite='storage-profile', kind='sp', mode='toolkit', cases=['inventory-freshness'],
                         languages=['EN'], mods=list(auxiliary.INVENTORY_MODS), options={})
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); cache = root / 'client1'; cache.mkdir()
            runtime = {'roles': {'client1': {'cache': str(cache)}}}
            auxiliary.stage(ROOT, root, root / 'game', root / 'jdk', selection,
                            {'PZSurvivorToolkit': ROOT / 'PZSurvivorToolkit'}, runtime)
            client = cache / 'mods/StorageProfileNative/42/media/lua/client'
            self.assertEqual({p.name for p in client.iterdir()}, {'ZZInventoryFreshness.lua'})
            self.assertEqual((client / 'ZZInventoryFreshness.lua').read_bytes(), (INTAKE / 'ZZInventoryFreshness.lua').read_bytes())
            (cache / 'console.txt').write_text(log(receipts()))
            result = auxiliary.verify(root, selection, {})
            self.assertFalse(result['issues']); self.assertEqual(result['outcomes'][0]['status'], 'passed')
            (cache / 'console.txt').write_text(log(receipts()) + '[STORAGE_PROFILE] FAIL test\n')
            self.assertEqual(auxiliary.verify(root, selection, {})['outcomes'][0]['status'], 'failed')

    def fixture_runtime(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime()
        lua.execute('''
            require=function(name) if name=='QueueTestSelection'then return {cases={'inventory-freshness'}}end return {}end
            Events={};for _,name in ipairs({'OnTick','OnMainMenuEnter','OnGameStart','OnPreUIDraw'})do
                Events[name]={Add=function(callback)Events[name].callback=callback end}
            end
        ''')
        fixture = lua.execute((INTAKE / 'ZZInventoryFreshness.lua').read_text() + '''
            return {equals=equals,observe=observe,unobserve=unobserve,expectedRows=expectedRows,publishedRow=publishedRow,
              seed=function(testPane,testPage,testInventory,testFoods,testPresenter,testOptions)
                pane=testPane;page=testPage;inventory=testInventory;foods=testFoods
                Presenter=testPresenter;Options=testOptions;activeMode='clean'
                phases={{mode='clean',view='hover'}};index=1;stage='observe';primaryPasses=0;publishedRows=nil
              end,
              failed=function()return observerFailure end,
              frame=function()return frame end}
        ''')
        return lua, fixture

    def test_observers_delegate_preserve_returns_restore_and_retain_failures(self):
        lua, fixture = self.fixture_runtime()
        lua.execute('''
            local fixture=...
            UIFont={Medium='medium'}
            getTextManager=function()return {MeasureStringX=function(_,_,text)return #text*5 end,getFontHeight=function()return 10 end}end
            instanceof=function(item,class)return item and item.food==true end
            local food={food=true,age=0,getOffAgeMax=function()return 10 end,getOffAge=function()return 5 end,
                getAge=function(self)return self.age end,setAge=function(self,value)self.age=value end,getID=function()return 1 end}
            local rows={{items={food,food},name='food'}}
            local rectCalls,textCalls=0,0
            local rect=function()rectCalls=rectCalls+1 end
            local text=function()textCalls=textCalls+1 end
            local pane={renderdetails=function()end,items=rows,headerHgt=10,itemHgt=20,column2=0,column3=150,height=100,
                getYScroll=function()return 0 end,getHeight=function()return 100 end,getIsVisible=function()return true end,
                drawRect=rect,drawText=text}
            local page={getIsVisible=function()return true end}
            local items={size=function()return 1 end,get=function()return food end}
            local inventory={getItems=function()return items end}
            local options={showFoodFreshnessBar=true,showFoodFreshnessPercentage=true}
            local fault={};local calls=0
            local presenter={draw=function(owner)
                calls=calls+1
                if calls==1 then error(fault,0)end
                return 'ok',nil,'tail'
            end}
            local original=presenter.draw;local instance=instanceof
            fixture.seed(pane,page,inventory,{food},presenter,options);fixture.observe()
            local ok,errorValue=pcall(presenter.draw,pane)
            assert(not ok and errorValue==fault,'original presenter failure changed')
            assert(food.age==0,'fixture age leaked after failure')
            assert(fixture.failed()==fault,'UI failure not retained')
            -- Inactive flags let a real forwarding-only presenter emit no output.
            options.showFoodFreshnessBar=false;options.showFoodFreshnessPercentage=false
            local a,b,c=presenter.draw(pane)
            assert(a=='ok'and b==nil and c=='tail','presenter returns changed')
            assert(fixture.failed()==fault,'later success hid failure')
            assert(fixture.frame().visits==0 and rectCalls==0 and textCalls==0)
            fixture.unobserve()
            assert(presenter.draw==original and pane.drawRect==rect and pane.drawText==text and instanceof==instance)
            fixture.observe();local foreign=function()end;presenter.draw=foreign
            assert(not pcall(fixture.unobserve),'foreign observer overwritten')
            assert(presenter.draw==foreign)
        ''', fixture)

    def test_new_pane_waits_for_completed_native_primary_publication(self):
        lua, fixture = self.fixture_runtime()
        lua.execute('''
            local fixture=...
            local food={}
            local rows={{items={food,food},name='food'}}
            local calls=0
            local pane={items={},drawRect=function()end,drawText=function()end,
              renderdetails=function(self,dragged)
                calls=calls+1
                if not dragged then self.items=rows end
                return 'native',nil,'tail'
              end}
            instanceof=function()return false end
            local presenter={draw=function()end}
            fixture.seed(pane,{}, {}, {food},presenter,{});fixture.observe()
            assert(fixture.publishedRow()==nil,'new pane consumed an unpublished map')
            pane:renderdetails(true)
            assert(fixture.publishedRow()==nil,'dragged pass published primary rows')
            local a,b,c=pane:renderdetails(false)
            assert(a=='native'and b==nil and c=='tail','native renderer returns changed')
            assert(fixture.publishedRow()==1 and pane.items==rows and calls==2)
            pane.items={}
            assert(not pcall(fixture.publishedRow),'replacement row map accepted without a primary render')
            fixture.unobserve()
        ''', fixture)

    def test_expected_rows_exclude_bottom_border_and_include_partial_content(self):
        lua, fixture = self.fixture_runtime()
        lua.execute('''
            local fixture=...
            UIFont={Medium='medium'}
            getTextManager=function()return {MeasureStringX=function()return 20 end,getFontHeight=function()return 10 end}end
            instanceof=function(item,class)return item.food==true end
            local food={food=true,getOffAgeMax=function()return 10 end,getOffAge=function()return 5 end,getAge=function()return 2 end}
            local pane={items={food,food},headerHgt=10,itemHgt=20,column2=0,column3=150,height=31,
              getYScroll=function()return 0 end,getHeight=function(self)return self.height end,getIsVisible=function()return true end}
            local page={getIsVisible=function()return true end}
            fixture.seed(pane,page,{}, {food},{},{showFoodFreshnessBar=true,showFoodFreshnessPercentage=true})
            local expected=fixture.expectedRows()
            assert(expected.foodRows==1,'row touching only lower border was visited')
            pane.height=31.5
            expected=fixture.expectedRows()
            assert(expected.foodRows==2,'partially visible content row was skipped')
        ''', fixture)

    def test_output_comparison_rejects_wrong_math_or_duplicate_calls(self):
        lua, fixture = self.fixture_runtime()
        lua.execute('''
            local fixture=...
            fixture.equals({{'52%',1,2}},{{'52%',1,2}})
            assert(not pcall(fixture.equals,{{'52%',1,2}},{{'53%',1,2}}))
            assert(not pcall(fixture.equals,{{'52%',1,2}},{{'52%',1,3}}))
            assert(not pcall(fixture.equals,{{1},{1}},{{1}}))
        ''', fixture)


if __name__ == '__main__': unittest.main()
