"""Cart key migration against native ModOptions; file IO is an offline double."""
import os
from pathlib import Path
import unittest

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/CartKeySettings.lua"
SHARED = ROOT / "PZSurvivorToolkit/42/media/lua/shared"
STORAGE = SHARED / "PZSurvivorToolkit/ModOptionsStorage.lua"
GAME = Path(os.environ.get("PZ_GAME", str(Path.home() / "Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java")))
NATIVE = GAME / "media/lua/client/PZAPI/ModOptions.lua"
MARKER = "PZSurvivorToolkitCartControls.ini"


@unittest.skipUnless(LuaRuntime is not None and NATIVE.is_file(), "Requires Lupa and native B42 ModOptions (PZ_GAME)")
class CartKeySettingsTests(unittest.TestCase):
    def boot(self, files=None, recovery_failure=False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            files = {}; writes = {}; fail = {}; silent = {}; closeFail = {}; truncate = {}
            Keyboard = {KEY_E=18, KEY_V=47}
            getText = function(text) return text end
            luautils = {split=function(text, separator)
                local parts = {}
                for value in (text .. separator):gmatch('(.-)%' .. separator) do
                    parts[#parts+1] = value
                end
                return parts
            end}
            getFileReader = function(path, create)
                local text = files[path]
                if text == nil then
                    if not create then return nil end
                    text = ''; files[path] = text
                end
                local lines = {}
                for line in text:gmatch('[^\r\n]+') do lines[#lines+1] = line end
                local index = 0
                return {readLine=function()
                    index=index+1; return lines[index]
                end, close=function() end}
            end
            getFileWriter = function(path, create, append)
                writes[path] = (writes[path] or 0)+1
                if fail[path] == 'open' then return nil end
                local buffer = append and (files[path] or '') or ''
                return {write=function(_, text)
                    if fail[path] == 'write' then error('injected write failure') end
                    buffer = buffer .. text
                end, close=function()
                    if closeFail[path] then error('injected close failure') end
                    if not silent[path] then
                        files[path] = truncate[path] and buffer:sub(1, truncate[path]) or buffer
                    end
                end}
            end
        ''')
        for path, text in (files or {}).items():
            lua.globals().files[path] = text
        lua.execute(NATIVE.read_text())
        lua.execute('''
            local options = PZAPI.ModOptions:create('SaucedCarts', 'Carts')
            binding = options:addKeyBind('PushCart', 'Push Cart', Keyboard.KEY_V)
            options:addTickBox('OtherCartOption', 'Other', false)
            PZAPI.ModOptions:create('AnotherMod'):addTextEntry('Name', 'Name', 'default')
        ''')
        lua.globals().storage = lua.execute(STORAGE.read_text())
        lua.execute("package.preload['PZSurvivorToolkit/ModOptionsStorage'] = function() return storage end")
        if recovery_failure:
            lua.execute("fail['ModOptions.ini']='open'")
        lua.execute((SHARED / '0000ToolkitModOptionsRecovery.lua').read_text())
        lua.globals().settings = lua.execute(HELPER.read_text())
        lua.execute('settings.configureDefault(binding); PZAPI.ModOptions:load()')
        return lua

    def test_new_default_and_restored_legacy_default_migrate_once(self):
        for persisted in (None, 47):
            with self.subTest(persisted=persisted):
                files = {} if persisted is None else {"ModOptions.ini": "keybind|SaucedCarts|PushCart|47\r\n"}
                lua = self.boot(files)
                self.assertEqual(lua.eval('binding.defaultkey'), 18)
                self.assertEqual(lua.eval('settings.migrate(binding)'), (True, 'preserved' if persisted is None else 'migrated'))
                self.assertEqual(lua.eval('binding:getValue()'), 18)
                self.assertEqual(lua.globals().writes['ModOptions.ini'], None if persisted is None else 1)
                self.assertEqual(lua.eval('settings.migrate(binding)'), (True, 'already_migrated'))

    def test_later_explicit_v_survives_restart_and_default_configuration(self):
        lua = self.boot({"ModOptions.ini": "keybind|SaucedCarts|PushCart|47\r\n"})
        self.assertEqual(lua.eval('settings.migrate(binding)'), (True, 'migrated'))
        lua.execute('binding:setValue(Keyboard.KEY_V); PZAPI.ModOptions:save()')
        files = dict(lua.globals().files.items())
        restarted = self.boot(files)
        restarted.execute('settings.configureDefault(binding)')
        self.assertEqual(restarted.eval('settings.migrate(binding)'), (True, 'already_migrated'))
        self.assertEqual(restarted.eval('binding:getValue()'), 47)
        self.assertIsNone(restarted.globals().writes['ModOptions.ini'])

    def test_custom_and_disabled_choices_finish_migration_without_options_save(self):
        for key in (0, 33, 18):
            with self.subTest(key=key):
                lua = self.boot({"ModOptions.ini": f"keybind|SaucedCarts|PushCart|{key}\r\n"})
                before = lua.globals().files['ModOptions.ini']
                self.assertEqual(lua.eval('settings.migrate(binding)'), (True, 'preserved'))
                self.assertEqual(lua.eval('binding:getValue()'), key)
                self.assertEqual(lua.globals().files['ModOptions.ini'], before)
                self.assertIsNone(lua.globals().writes['ModOptions.ini'])
                lua.execute('binding:setValue(Keyboard.KEY_V); PZAPI.ModOptions:save()')
                restarted = self.boot(dict(lua.globals().files.items()))
                self.assertEqual(restarted.eval('settings.migrate(binding)'), (True, 'already_migrated'))
                self.assertEqual(restarted.eval('binding:getValue()'), 47)

    def test_native_save_preserves_registered_and_absent_mod_options(self):
        lua = self.boot({"ModOptions.ini": (
            "keybind|SaucedCarts|PushCart|47\r\n"
            "tickbox|SaucedCarts|OtherCartOption|true\r\n"
            "textentry|AnotherMod|Name|Chosen name\r\n"
            "keybind|AbsentOne|Bind|29\r\n"
            "tickbox|AbsentTwo|Enabled|false\r\n")})
        lua.execute('originalOtherOptions=PZAPI.ModOptions.OtherOptions; binding.element={keyCode=47}')
        self.assertEqual(lua.eval('settings.migrate(binding)'), (True, 'migrated'))
        self.assertEqual(lua.eval('binding.element.keyCode'), 18)
        self.assertTrue(lua.eval('originalOtherOptions == PZAPI.ModOptions.OtherOptions'))
        restarted = self.boot(dict(lua.globals().files.items()))
        self.assertTrue(restarted.eval("PZAPI.ModOptions:getOptions('SaucedCarts'):getOption('OtherCartOption'):getValue()"))
        self.assertEqual(restarted.eval("PZAPI.ModOptions:getOptions('AnotherMod'):getOption('Name'):getValue()"), 'Chosen name')
        self.assertEqual(list(restarted.eval('PZAPI.ModOptions.OtherOptions').values()),
                         ['keybind|AbsentOne|Bind|29', 'tickbox|AbsentTwo|Enabled|false'])

    def test_storage_saves_multiple_targets_and_preserves_other_lines(self):
        lua = self.boot({"ModOptions.ini": (
            "keybind|SaucedCarts|PushCart|47\r\n"
            "tickbox|SaucedCarts|OtherCartOption|true\r\n"
            "keybind|AbsentOne|Bind|29\r\n"
            "tickbox|AbsentTwo|Enabled|false\r\n")})
        lua.execute("binding:setValue(18); PZAPI.ModOptions:getOptions('SaucedCarts'):getOption('OtherCartOption'):setValue(false)")
        expected = lua.table_from({'keybind|SaucedCarts|PushCart|': '18',
                                   'tickbox|SaucedCarts|OtherCartOption|': 'false'})
        self.assertTrue(lua.globals().storage.save(expected))
        restarted = self.boot(dict(lua.globals().files.items()))
        self.assertEqual(list(restarted.eval('PZAPI.ModOptions.OtherOptions').values()),
                         ['keybind|AbsentOne|Bind|29', 'tickbox|AbsentTwo|Enabled|false'])
        expected['tickbox|SaucedCarts|OtherCartOption|'] = 'true'
        self.assertFalse(lua.globals().storage.save(expected))

    def test_storage_restores_other_options_after_save_failure(self):
        lua = self.boot({"ModOptions.ini": "keybind|AbsentOne|Bind|29\r\n"})
        lua.execute("originalOtherOptions=PZAPI.ModOptions.OtherOptions; fail['ModOptions.ini']='write'")
        self.assertFalse(lua.globals().storage.save(lua.table_from({})))
        self.assertTrue(lua.eval('originalOtherOptions == PZAPI.ModOptions.OtherOptions'))

    def test_options_open_write_close_and_silent_failures_do_not_mark_success(self):
        for failure in ('open', 'write', 'close', 'silent'):
            with self.subTest(failure=failure):
                lua = self.boot({"ModOptions.ini": "keybind|SaucedCarts|PushCart|47\r\n"})
                table = 'closeFail' if failure == 'close' else 'silent' if failure == 'silent' else 'fail'
                lua.globals()[table]['ModOptions.ini'] = True if failure in ('close', 'silent') else failure
                self.assertEqual(lua.eval('settings.migrate(binding)'), (False, 'binding_save'))
                self.assertEqual(lua.eval('binding:getValue()'), 47)
                self.assertIsNone(lua.globals().files[MARKER])
                self.assertIsNone(lua.globals().writes[MARKER])

    def test_marker_write_failure_is_reported_and_retry_can_complete(self):
        for failure in ('open', 'write', 'close', 'silent'):
            with self.subTest(failure=failure):
                lua = self.boot({"ModOptions.ini": "keybind|SaucedCarts|PushCart|47\r\n"})
                table = 'closeFail' if failure == 'close' else 'silent' if failure == 'silent' else 'fail'
                lua.globals()[table][MARKER] = True if failure in ('close', 'silent') else failure
                self.assertEqual(lua.eval('settings.migrate(binding)'), (False, 'marker_write'))
                self.assertNotEqual(lua.globals().files[MARKER], 'PushCartInteract=1\r\n')
                self.assertIn('keybind|SaucedCarts|PushCart|18', lua.globals().files['ModOptions.ini'])
                lua.globals()[table][MARKER] = None
                self.assertEqual(lua.eval('settings.migrate(binding)'), (True, 'preserved'))
                self.assertEqual(lua.globals().writes['ModOptions.ini'], 1)

    def test_silent_partial_save_after_key_line_does_not_finish_migration(self):
        lua = self.boot({"ModOptions.ini": (
            "keybind|SaucedCarts|PushCart|47\r\n"
            "textentry|AnotherMod|Name|Keep me\r\n")})
        lua.globals().truncate['ModOptions.ini'] = len('keybind|SaucedCarts|PushCart|18\r\n')
        self.assertEqual(lua.eval('settings.migrate(binding)'), (False, 'binding_save'))
        self.assertEqual(lua.eval('binding:getValue()'), 47)
        self.assertIsNone(lua.globals().writes[MARKER])

    def test_late_recovery_reloads_legacy_binding_before_once_only_decision(self):
        original = 'keybind|SaucedCarts|PushCart|47\r\nkeybind|Absent|Keep|29\r\n'
        seed = self.boot({'ModOptions.ini': original})
        seed.execute('binding:setValue(18)')
        seed.globals().truncate['ModOptions.ini'] = len('keybind|SaucedCarts|PushCart|18\r\n')
        self.assertFalse(seed.globals().storage.save(seed.table_from({'keybind|SaucedCarts|PushCart|': '18'})))
        image = dict(seed.globals().files.items())
        # Model the native-write crash boundary; the serializer/IO doubles above
        # have already exercised and retained the same sealed before-image.
        image['ModOptions.ini'] = 'keybind|SaucedCarts|PushCart|18\r\n'
        restarted = self.boot(image, recovery_failure=True)
        self.assertEqual(18, restarted.eval('binding:getValue()'), 'upstream loaded the interrupted file')
        restarted.execute("fail['ModOptions.ini']=nil")
        self.assertEqual((True, 'migrated'), restarted.eval('settings.migrate(binding)'))
        self.assertIn('keybind|Absent|Keep|29', restarted.globals().files['ModOptions.ini'])
        self.assertEqual(18, restarted.eval('binding:getValue()'))


if __name__ == '__main__':
    unittest.main()
