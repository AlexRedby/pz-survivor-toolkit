"""Receipt retries and reconnects must preserve exactly the same item evidence."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('native_tags', Path(__file__).parent / 'native_tags/run.py')
native_tags = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native_tags)


class ReceiptChecks(unittest.TestCase):
    def setUp(self):
        self.receipt = dict(actor='client1', phase='enabled', exact=True,
                            originalInventoryUnchanged=True, ids={'42': {'source': 0, 'destination': 1}})

    def test_retry_and_reconnect_reuse_identical_ids(self):
        native_tags.validate_receipts([self.receipt, copy.deepcopy(self.receipt)], 'client1', ['enabled'])

    def test_missing_or_changed_authority_evidence_is_rejected(self):
        changed = copy.deepcopy(self.receipt)
        changed['ids']['42']['destination'] = 0
        for receipts in ([], [changed, self.receipt], [dict(self.receipt, exact=False)],
                         [dict(self.receipt, originalInventoryUnchanged=False)]):
            with self.subTest(receipts=receipts), self.assertRaises(AssertionError):
                native_tags.validate_receipts(receipts, 'client1', ['enabled'])

    def test_reconnect_requires_both_authority_epochs(self):
        before = dict(self.receipt, reconnected=False)
        after = dict(self.receipt, reconnected=True)
        native_tags.validate_reconnect_receipts([before, after], 'client1', 'enabled')
        for invalid in ([before], [after], [self.receipt, before], [dict(before, actor='client2'), after]):
            with self.subTest(receipts=invalid), self.assertRaises(AssertionError):
                native_tags.validate_reconnect_receipts(invalid, 'client1', 'enabled')


class PlacementChecks(unittest.TestCase):
    def test_both_load_acknowledgements_precede_native_creation(self):
        import json
        ready = lambda actor, signature='same': '[TAG_PLACEMENT_READY] ' + json.dumps(dict(actor=actor, signature=signature))
        created = lambda actor: '[TAG_PLACEMENT] ' + json.dumps(dict(actor=actor))
        valid = [ready('client1'), ready('client2'), created('client1'), created('client2')]
        native_tags.validate_placement_order('\n'.join(valid))
        for invalid in ([ready('client1'), created('client1'), ready('client2'), created('client2')],
                        [ready('client1'), ready('client2', 'other'), *valid[2:]],
                        valid + [created('client1')], valid[:-1]):
            with self.subTest(log=invalid), self.assertRaises(AssertionError):
                native_tags.validate_placement_order('\n'.join(invalid))


class PlantingChecks(unittest.TestCase):
    def setUp(self):
        self.items = {key: dict(id=index + 11, fullType=value)
                      for index, (key, value) in enumerate(native_tags.PLANTING_TYPES.items())}
        self.records = [('[TAG_RECEIPT] ', dict(actor='client1', ids={'1': {}})),
                        ('[TAG_PLANTING_SETUP] ', dict(actor='client1', items=self.items))]
        for phase, revision in [('setup', 1), ('seed', 2), ('reset', 2), ('exclude', 3), ('restored', 4), ('restored', 4)]:
            facts = {}
            for key, item in self.items.items():
                dest = key in native_tags.PLANTING_SEEDS if phase == 'seed' else phase in ('exclude', 'restored') and key == 'candy'
                facts[str(item['id'])] = dict(item=key, fullType=item['fullType'], source=int(not dest),
                                              destination=int(dest), expected='destination' if dest else 'source')
            self.records.append(('[TAG_PLANTING_RECEIPT] ', dict(actor='client1', phase=phase, ids=facts,
                                 revision=revision, exact=True, originalInventoryUnchanged=True, manualUnchanged=True,
                                 reconnected=len(self.records) == 7)))
        for phase, revision in [('seed', 2), ('exclude', 3)]:
            self.records.append(('[TAG_PLANTING_RULE] ', dict(actor='client1', phase=phase, revision=revision,
                                 rule=dict(mode='all', include=['seed'] if phase == 'seed' else ['food'],
                                           exclude=[] if phase == 'seed' else ['seed']), manualUnchanged=True)))
        self.records.append(('[TAG_PLANTING_CATALOG] ', dict(actor='client1', plantingTypes=75, fullPackets=55, emptyPackets=55)))

    def validate(self, records):
        ui = dict(actor='client1', visibleIDs=[self.items[key]['id'] for key in native_tags.PLANTING_SEEDS],
                  previewNames=list(native_tags.PLANTING_SEEDS), sameSnackCategory=True,
                  foodPreserved=True, medicalPreserved=True, legacyPreserved=True)
        return native_tags.validate_planting_receipts('\n'.join(marker + json.dumps(row)
            for marker, row in [*records, ('[TAG_PLANTING_UI] ', ui)]), 'client1')

    def test_twenty_cases_keep_original_sixteen_and_exact_reconnect_evidence(self):
        self.assertEqual(native_tags.PLANTING_CASES[:15], native_tags.CASES[:15])
        self.assertEqual(len(native_tags.PLANTING_CASES), 20)
        self.assertEqual(native_tags.PLANTING_CASES[-1], 'rule-reconnect')
        self.assertEqual(len(self.validate(self.records)), 6)

    def test_recreated_missing_or_changed_identity_and_negative_moves_are_rejected(self):
        invalid = []
        invalid.append(self.records + [copy.deepcopy(self.records[1])])
        invalid.append([row for row in self.records if row[1].get('phase') != 'reset'])
        changed = copy.deepcopy(self.records)
        changed[3][1]['ids'].pop(str(self.items['sunflower']['id']))
        invalid.append(changed)
        for key in ('candy', 'emptyPacket', 'hemp'):
            changed = copy.deepcopy(self.records)
            changed[3][1]['ids'][str(self.items[key]['id'])].update(source=0, destination=1, expected='destination')
            invalid.append(changed)
        invalid.append(self.records[:7] + self.records[8:])
        for records in invalid:
            with self.subTest(records=records), self.assertRaises(AssertionError):
                self.validate(records)

    def test_catalog_evidence_requires_one_actor_record_with_all_exact_counts(self):
        catalog = self.records[-1]
        invalid = [self.records[:-1], [*self.records, copy.deepcopy(catalog)]]
        for key in ('plantingTypes', 'fullPackets', 'emptyPackets', 'actor'):
            changed = copy.deepcopy(self.records)
            changed[-1][1][key] = 'client2' if key == 'actor' else changed[-1][1][key] - 1
            invalid.append(changed)
        for records in invalid:
            with self.subTest(records=records), self.assertRaises(AssertionError):
                self.validate(records)

    def test_native_catalog_checks_item_roles_and_deduplicates_scripts(self):
        try:
            from lupa.lua51 import LuaRuntime, LuaError
        except ImportError:
            self.skipTest('Lua fixture checks require the existing Lupa test dependency')
        lua = LuaRuntime(unpack_returned_tuples=True)
        source = (Path(__file__).parent / 'native_tags/client/ZZTagBaseline.lua').read_text()
        start = source.index(' local function checkPlantingCatalog()')
        finish = source.index(' add(function()', start)
        lua.execute('''
            function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
            local scripts,inputs,packets,outputs={},{},{},{}
            farming_vegetableconf={props={}}
            function script(name,seed)
                local value={seed=seed,farming=true,category='native-category',getFullName=function() return name end,
                    getDisplayCategory=function(self) return self.category end}
                scripts[name]=value;return value
            end
            for index=1,75 do
                local value=script('Base.Seed'..index,true);inputs[index]=value
                farming_vegetableconf.props[index]={seedTypes={value:getFullName(),value:getFullName()}}
            end
            for index=1,55 do
                packets[index]=script('Base.Packet'..index,true)
                outputs[#outputs+1]=inputs[index];outputs[#outputs+1]=script('Base.Empty'..index,false)
            end
            packets[#packets+1]=packets[1];outputs[#outputs+1]=outputs[2]
            ScriptManager={instance={getItem=function(_,name) return scripts[name] end,getCraftRecipe=function()
                return {getInputs=function() return list({{getPossibleInputItems=function() return list(packets) end}}) end,
                    getOutputs=function() return list({{getPossibleResultItems=function() return list(outputs) end}}) end}
            end}}
            Tags={forScriptItem=function(value) return value end,category=function(value) return value.category end,
                matches=function(value,ids) return ids[1]=='farming' and value.farming or ids[1]=='seed' and value.seed end}
            user='client1';catalogEvents=0
            json={encode=function(value)
                assert(value.actor==user and value.plantingTypes==75 and value.fullPackets==55 and value.emptyPackets==55)
                catalogEvents=catalogEvents+1;return '{}'
            end}
            print=function() end
        ''')
        check = lua.execute(source[start:finish] + '\nreturn checkPlantingCatalog')
        check()
        self.assertEqual(lua.globals().catalogEvents, 1)
        lua.execute("farming_vegetableconf.props[1].seedTypes={'Missing.Script'}")
        with self.assertRaisesRegex(LuaError, 'native planting script missing'):
            check()
        lua.execute("farming_vegetableconf.props[1].seedTypes={'Base.Empty1'}")
        with self.assertRaisesRegex(LuaError, 'native catalog planting role differs'):
            check()
        lua.execute("farming_vegetableconf.props[1].seedTypes={'Base.Seed1'};ScriptManager.instance:getItem('Base.Empty1').seed=true")
        with self.assertRaisesRegex(LuaError, 'native catalog planting role differs'):
            check()

    def test_planting_editor_waits_for_native_owner_and_editor_registration_before_apply(self):
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            self.skipTest('Lua fixture checks require the existing Lupa test dependency')
        lua = LuaRuntime(unpack_returned_tuples=True)
        fixture_root = Path(__file__).parent / 'native_tags'
        lua.globals().FixtureRoot = str(fixture_root)
        lua.execute('''
            Fixture=dofile(FixtureRoot..'/shared/TagFixture.lua')
            local function panel()
                return {registered=false,getIsVisible=function() return true end,
                    isReallyVisible=function(self) return self.registered end}
            end
            applied,saved,now,traces,rowOpens,buttonOpens=0,0,3000,{},0,0
            user='client1';batteryCategory='BatteryCategory'
            getTimestampMs=function() return now end
            json={encode=function(value) traces[#traces+1]=value;return '{}' end};print=function() end
            LootSorter={openPicker=function()
                local owner=panel();LootSorter._picker=owner
                owner.selectedCats={toolElectrical=true,craftingElectrical_material=true,BatteryCategory=true}
                owner.selectedItems={['Manual item']=true}
                local function openEditor()
                    local editor=panel();owner.toolkitRulePicker=editor;editor.owner=owner
                    editor.applyButton={onclick=function()
                        assert(owner.registered and editor.registered and not owner.removed and not editor.removed)
                        applied=applied+1;owner.toolkitTagRule=editor.draft
                    end}
                end
                local seedRow={tag='seed',requiresRule=true,label='Localized seed label'}
                owner.listbox={items={{item={tag='food',label='Food'}},{item=seedRow}},onmousedown=function(target,row)
                    assert(target==owner and row==seedRow);rowOpens=rowOpens+1;openEditor()
                end}
                owner.toolkitTagRuleButton={onclick=function(target)
                    assert(target==owner);buttonOpens=buttonOpens+1;openEditor()
                end}
                owner.btnSave={onclick=function() saved=saved+1 end}
            end}
            selectRule=function(include,exclude,mode)
                LootSorter._picker.toolkitRulePicker.draft={include=include,exclude=exclude,mode=mode}
            end
        ''')
        source = (fixture_root / 'client/ZZTagBaseline.lua').read_text()
        start = source.index('local function openPlantingRule(phase)')
        finish = source.index('local function awaitPlantingRule(phase)', start)
        opened, apply = lua.execute(source[start:finish] + '\nreturn openPlantingRule,applyPlantingRule')
        for index, phase in enumerate(('seed', 'exclude', 'restored')):
            opened(phase)
            self.assertEqual(lua.globals().rowOpens, 1)
            self.assertEqual(lua.globals().buttonOpens, index)
            self.assertEqual(lua.globals().applied, index)
            self.assertFalse(apply(phase))
            lua.execute('assert(not picker.registered and not rulePicker.registered);picker.registered=true')
            self.assertFalse(apply(phase))
            lua.execute('rulePicker.registered=true;picker.removed=true')
            self.assertFalse(apply(phase))
            lua.execute('picker.removed=nil;rulePicker.removed=true')
            self.assertFalse(apply(phase))
            lua.execute('rulePicker.removed=nil')
            self.assertTrue(apply(phase))
            self.assertEqual(lua.globals().applied, index + 1)
            self.assertEqual(lua.globals().saved, index + 1)
            lua.execute('''
                local categories=0
                for key,value in pairs(picker.selectedCats) do
                    assert(value and (key=='toolElectrical' or key=='craftingElectrical_material' or key=='BatteryCategory'))
                    categories=categories+1
                end
                local items=0
                for key,value in pairs(picker.selectedItems) do assert(key=='Manual item' and value);items=items+1 end
                assert(categories==3 and items==1)
                now=now+3000
            ''')
        self.assertEqual(len(lua.globals().traces), 3)


if __name__ == '__main__':
    unittest.main()
