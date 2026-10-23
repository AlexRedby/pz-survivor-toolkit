import importlib.util
import os
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('generate_item_categories', ROOT / 'tools/generate_item_categories.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class CategoryDataTests(unittest.TestCase):
    def test_base_module_fallback_exact_key_order_comments_and_dummy_names(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selected = root / 'selected.ini'
            selected.write_text('Mods=Toolkit;ArcheryNexus\n')
            (root / 'organizedCategories_core.lua').write_text('''
                TweakItem("Base.Thread","DisplayCategory","craftingTailoring_material")
                TweakItem("Base.","DisplayCategory","ignored")
                TweakItem("Base.Revolver_Long","DisplayCategory","weaponFirearm_P44")
                -- TweakItem("Base.Thread","DisplayCategory","comment")
            ''')
            (root / 'a.lua').write_text('''
                require("organizedCategories_core")
                TweakItem("Base.Thread","DisplayCategory","ordered_first")
                TweakItem("Base.Revolver_long","DisplayCategory","weaponFirearm_P357")
            ''')
            (root / 'z.lua').write_text('''
                if not OrganizedCategories.handsortNeedsMod("ArcheryNexus") then return end
                TweakItem("BASE.Thread","DisplayCategory","ordered_last")
                TweakItem("Base.Revolver_Long","DisplayCategory","weaponFirearm_P44")
            ''')
            (root / 'zz.lua').write_text('''
                if not OrganizedCategories.handsortNeedsMod("MissingPack") then return end
                TweakItem("Base.Thread","DisplayCategory","not_selected")
            ''')
            text = generator.render(root, selected)
            self.assertIn('["base.thread"] = "ordered_last"', text)
            self.assertNotIn('["base."]', text)
            self.assertIn('["base.thread"] = "ordered_last"', text)
            self.assertIn('["base.revolver_long"] = "weaponFirearm_P357"', text)
            self.assertIn('zz.lua', text)
            self.assertNotIn('"comment"', text)

    @unittest.skipUnless(os.environ.get('OC_CLASSIFIER_SOURCE'), 'set OC_CLASSIFIER_SOURCE for upstream parity')
    def test_reviewed_source_execution_matches_owned_data(self):
        from lupa.lua51 import LuaRuntime
        source = Path(os.environ['OC_CLASSIFIER_SOURCE'])
        selected = ROOT / 'SurvivorQoL-selected.ini'
        rendered = generator.render(source, selected)
        self.assertEqual(rendered, generator.TARGET.read_text())
        modules = set(re.search(r'^Mods=(.*)$', selected.read_text(), re.M)[1].split(';'))
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().active = lua.table_from({name: True for name in modules})
        lua.globals().sourcePath = str(source)
        lua.execute('''
            actual, insertion, backing = {}, {}, {}
            TweakItemData=setmetatable({}, {__index=backing,__newindex=function(_,name,value)
                if backing[name]==nil then insertion[#insertion+1]=name end
                backing[name]=value
            end})
            local pairsLua=pairs
            pairs=function(value)
                if value~=TweakItemData then return pairsLua(value) end
                local index=0
                return function()
                    index=index+1;local key=insertion[index]
                    if key then return key,backing[key] end
                end
            end
            getActivatedMods=function() return {contains=function(_,id)return active[id]==true end,
                size=function()return 0 end} end
            -- Native B42.21 getModule(name) returns Base when name is absent.
            ScriptManager={instance={getModule=function()return {name='Base'} end}}
            Events={OnGameBoot={Add=function()end}}
            require=function()end
        ''')
        lua.execute((source / 'ItemTweaker_Core.lua').read_text())
        self.assertTrue(lua.eval('OrganizedCategories.handsortNeedsMod')("AbsentAddon"))
        # Run actual source declarations and mirroring, preserving native Kahlua's
        # exact-key insertion order before the precedence snapshot normalizes keys.
        for name in re.findall(r'^-- (\S+\.lua) [0-9a-f]{64}$', rendered, re.M):
            lua.execute((source / name).read_text())
        lua.execute('''
            for _,name in ipairs(insertion) do
                local category=backing[name].DisplayCategory or backing[name].displaycategory
                if category then actual[name:lower()]=category end
            end
        ''')
        expected = lua.execute(rendered)
        self.assertEqual(dict(lua.globals().actual.items()), dict(expected.items()))
        self.assertGreater(len(dict(expected.items())), 50000)


if __name__ == '__main__':
    unittest.main()
