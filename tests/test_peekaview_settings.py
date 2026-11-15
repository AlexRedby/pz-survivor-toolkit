"""One-time preset against installed native ModOptions and upstream Peek a View.

PZ_GAME selects the game Java directory; PZ_PEEKAVIEW_SOURCE selects the Workshop
mod root. File IO, events, UI controls and Java setters are doubles, not a game run.
"""
import os
from pathlib import Path
import re
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'PZSurvivorToolkit/42/media/lua/client'
SHARED = ROOT / 'PZSurvivorToolkit/42/media/lua/shared'
GAME = Path(os.environ.get('PZ_GAME', str(Path.home() / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java')))
UPSTREAM = Path(os.environ.get('PZ_PEEKAVIEW_SOURCE', str(Path.home() / 'Library/Application Support/Steam/steamapps/workshop/content/108600/3710281407/mods/PeekAView')))
NATIVE = GAME / 'media/lua/client/PZAPI/ModOptions.lua'
OPTIONS = UPSTREAM / '42.21/media/lua/client/PeekAView_Options.lua'
MARKER = 'PZSurvivorToolkitPeekAView.ini'
PREFIX = 'tickbox|PeekAView|'


@unittest.skipUnless(NATIVE.is_file() and OPTIONS.is_file(), 'Requires PZ_GAME and PZ_PEEKAVIEW_SOURCE for source-backed preset checks')
class PeekAViewSettingsTests(unittest.TestCase):
    def boot(self, files=None, active=True, java=True, upstream_first=False, fire=True):
        lua = LuaRuntime(unpack_returned_tuples=True)
        sources = {
            'PZAPI/ModOptions': NATIVE,
            'PeekAView_Options': OPTIONS,
            '0000ToolkitModOptionsRecovery': SHARED / '0000ToolkitModOptionsRecovery.lua',
            'PZSurvivorToolkit/ModOptionsStorage': SHARED / 'PZSurvivorToolkit/ModOptionsStorage.lua',
            **{'PZSurvivorToolkit/' + name: CLIENT / 'PZSurvivorToolkit' / (name + '.lua')
               for name in ('PeekAViewSettings',)},
        }
        lua.globals().loadSource = lambda name: sources[name].read_text()
        lua.globals().active = active
        lua.execute(r'''
            files={}; writes={}; failures={}; silent={}; logs={}; javaValues={}
            getText=function(key)return key end
            luautils={split=function(text,separator)
                local parts={}
                for value in (text..separator):gmatch('(.-)%'..separator) do parts[#parts+1]=value end
                return parts
            end}
            function getActivatedMods()return {contains=function(_,id)return active and id=='PeekAView'end}end
            Events={OnGameBoot={callbacks={}}}
            function Events.OnGameBoot.Add(fn)
                for _,old in ipairs(Events.OnGameBoot.callbacks) do if old==fn then return end end
                table.insert(Events.OnGameBoot.callbacks,fn)
            end
            function Events.OnGameBoot.Remove(fn)
                for i=#Events.OnGameBoot.callbacks,1,-1 do
                    if Events.OnGameBoot.callbacks[i]==fn then table.remove(Events.OnGameBoot.callbacks,i)end
                end
            end
            function bootEvent()for _,fn in ipairs(Events.OnGameBoot.callbacks)do fn()end end
            function getFileReader(path,create)
                if failures[path]=='read' then error('read failure')end
                if files[path]==nil then if not create then return nil end;files[path]='' end
                local lines={};for line in files[path]:gmatch('[^\r\n]+')do lines[#lines+1]=line end
                local i=0
                return {readLine=function()i=i+1;return lines[i]end,close=function()end}
            end
            function getFileWriter(path,create,append)
                writes[path]=(writes[path]or 0)+1
                if failures[path]=='open' then return nil end
                local buffer=append and(files[path]or '')or ''
                return {write=function(_,text)
                    if failures[path]=='write' then error('write failure')end
                    buffer=buffer..text
                end,close=function()
                    if failures[path]=='close' then error('close failure')end
                    if not silent[path] then files[path]=buffer end
                end}
            end
            function require(name)
                if package.loaded[name]then return package.loaded[name]end
                local result=assert(loadstring(loadSource(name),'@'..name..'.lua'))()
                package.loaded[name]=result or true;return package.loaded[name]
            end
            function print(text)logs[#logs+1]=text end
            PeekAViewMod=setmetatable({}, {__index=function(_,name)
                if name=='isExternalStairFeatureActive' then return function()return false end end
                return function(value)javaValues[name]=value end
            end})
        ''')
        if not java:
            lua.execute('PeekAViewMod=nil')
        for name, contents in (files or {}).items():
            lua.globals().files[name] = contents
        if upstream_first:
            lua.execute("require 'PZAPI/ModOptions'; require 'PeekAView_Options'")
        lua.execute((CLIENT / '000ToolkitPeekAViewSettings.lua').read_text())
        if active:
            lua.execute("PZAPI.ModOptions:create('AnotherMod'):addTextEntry('Name','Name','default')")
        if fire:
            lua.execute('bootEvent()')
        return lua

    def option(self, lua, name):
        return lua.eval("PZAPI.ModOptions:getOptions('PeekAView')")['dict'][name]

    def test_existing_true_settings_migrate_once_in_either_load_order(self):
        for upstream_first in (False, True):
            with self.subTest(upstream_first=upstream_first):
                lua = self.boot({'ModOptions.ini': PREFIX + 'treeFadeActiveInVehicle|true\r\n' + PREFIX + 'fixB42Adjacency|true\r\n'}, upstream_first=upstream_first)
                for name in ('treeFadeActiveInVehicle', 'fixB42Adjacency'):
                    self.assertFalse(self.option(lua, name)['value'])
                self.assertFalse(lua.globals().javaValues['setTreeFadeActiveInVehicle'])
                self.assertFalse(lua.globals().javaValues['setFixB42Adjacency'])
                self.assertEqual(lua.globals().files[MARKER], 'NativeVisibility42.22=1\r\n')
                lua.execute('bootEvent()')
                self.assertEqual(lua.globals().writes['ModOptions.ini'], 1)
                self.assertEqual(lua.globals().writes[MARKER], 1)

    def test_new_profile_and_declined_jar_store_the_same_preset(self):
        for java in (True, False):
            with self.subTest(java=java):
                lua = self.boot(java=java)
                self.assertIn(PREFIX + 'treeFadeActiveInVehicle|false', lua.globals().files['ModOptions.ini'])
                self.assertIn(PREFIX + 'fixB42Adjacency|false', lua.globals().files['ModOptions.ini'])
                self.assertIsNotNone(lua.globals().files[MARKER])

    def test_unrelated_preferences_and_absent_mods_survive_reload(self):
        initial = (PREFIX + 'enable|false\r\n' + PREFIX + 'cutawayActiveInVehicle|false\r\n'
                   + PREFIX + 'treeFadeActiveOnFoot|false\r\n' + PREFIX + 'stairEnabled|false\r\n'
                   + 'slider|PeekAView|cutawayRange|15\r\ntextentry|AnotherMod|Name|Chosen\r\n'
                   + 'tickbox|AbsentOne|Enabled|true\r\nkeybind|AbsentTwo|Key|29\r\n')
        lua = self.boot({'ModOptions.ini': initial})
        for line in initial.splitlines():
            self.assertIn(line, lua.globals().files['ModOptions.ini'].splitlines())
        restarted = self.boot(dict(lua.globals().files.items()))
        self.assertIsNone(restarted.globals().writes['ModOptions.ini'])
        self.assertFalse(self.option(restarted, 'stairEnabled')['value'])
        self.assertFalse(restarted.globals().javaValues['setCutawayActiveInVehicle'])
        self.assertEqual(self.option(restarted, 'cutawayRange')['value'], 15)
        self.assertEqual(list(restarted.eval('PZAPI.ModOptions.OtherOptions').values()),
                         ['tickbox|AbsentOne|Enabled|true', 'keybind|AbsentTwo|Key|29'])

    def test_later_native_ui_apply_and_restart_preserve_deliberate_changes(self):
        lua = self.boot()
        main = (GAME / 'media/lua/client/OptionScreens/MainOptions.lua').read_text()
        section = main.split('elseif option.type == "tickbox" then', 1)[1].split('elseif option.type == "multipletickbox" then', 1)[0]
        body = re.search(r'function gameOption.apply\(self\)(.*?)\n\s*end\n\s*function gameOption.onChange', section, re.S)
        self.assertIsNotNone(body, 'Native tickbox Apply contract changed')
        lua.globals().nativeApplyBody = body.group(1)
        lua.execute('''
            PZAPI.ModOptions:load()
            local option=PZAPI.ModOptions:getOptions('PeekAView'):getOption('treeFadeActiveInVehicle')
            local source='return function(option) return function(self)'..nativeApplyBody..' end end'
            local apply=assert(loadstring(source))()(option)
            apply({control={isSelected=function()return true end}})
            PZAPI.ModOptions:save()
        ''')
        self.assertTrue(lua.globals().javaValues['setTreeFadeActiveInVehicle'])
        restarted = self.boot(dict(lua.globals().files.items()))
        self.assertTrue(self.option(restarted, 'treeFadeActiveInVehicle')['value'])
        self.assertTrue(restarted.globals().javaValues['setTreeFadeActiveInVehicle'])
        self.assertFalse(self.option(restarted, 'fixB42Adjacency')['value'])
        self.assertIsNone(restarted.globals().writes['ModOptions.ini'])

    def test_save_or_marker_failures_do_not_complete_the_migration(self):
        for path in ('ModOptions.ini', MARKER):
            for failure in ('open', 'write', 'close', 'silent'):
                with self.subTest(path=path, failure=failure):
                    lua = self.boot({'ModOptions.ini': PREFIX + 'treeFadeActiveInVehicle|true\r\n'}, fire=False)
                    if failure == 'silent':
                        lua.globals().silent[path] = True
                    else:
                        lua.globals().failures[path] = failure
                    lua.execute('bootEvent()')
                    self.assertNotEqual(lua.globals().files[MARKER], 'NativeVisibility42.22=1\r\n')
                    self.assertGreater(lua.eval('#logs'), 0)
                    self.assertFalse(lua.globals().javaValues['setTreeFadeActiveInVehicle'])
                    lua.globals().silent[path] = None
                    lua.globals().failures[path] = None
                    lua.execute('bootEvent()')
                    self.assertIsNotNone(lua.globals().files[MARKER])

    def test_inactive_mod_and_changed_option_contract_leave_profile_untouched(self):
        lua = self.boot(active=False)
        self.assertEqual(lua.eval('#Events.OnGameBoot.callbacks'), 0)
        self.assertEqual(dict(lua.globals().writes.items()), {})
        lua = self.boot(fire=False)
        lua.execute("PZAPI.ModOptions:getOptions('PeekAView').dict.fixB42Adjacency=nil; bootEvent()")
        self.assertEqual(dict(lua.globals().writes.items()), {})
        self.assertIsNone(lua.globals().files[MARKER])
        self.assertTrue(lua.globals().javaValues['setTreeFadeActiveInVehicle'])

    def test_reloading_bootstrap_does_not_duplicate_the_preset_callback(self):
        lua = self.boot(fire=False)
        lua.execute((CLIENT / '000ToolkitPeekAViewSettings.lua').read_text())
        self.assertEqual(lua.eval('#Events.OnGameBoot.callbacks'), 2)
        lua.execute('bootEvent()')
        self.assertEqual(lua.globals().writes[MARKER], 1)

    def test_swallowed_java_setter_errors_do_not_mark_the_preset_complete(self):
        for setter in ('setTreeFadeActiveInVehicle', 'setFixB42Adjacency'):
            for failure in ('missing', 'throw'):
                with self.subTest(setter=setter, failure=failure):
                    lua = self.boot(fire=False)
                    lua.globals().setter = setter
                    lua.execute("PeekAViewMod[setter]=" + ('false' if failure == 'missing' else "function()error('setter failed')end"))
                    lua.execute('bootEvent()')
                    self.assertIsNotNone(lua.eval('PeekAView.lastJavaError'))
                    self.assertIsNone(lua.globals().files[MARKER])
                    self.assertIsNone(lua.globals().writes['ModOptions.ini'])


if __name__ == '__main__':
    unittest.main()
