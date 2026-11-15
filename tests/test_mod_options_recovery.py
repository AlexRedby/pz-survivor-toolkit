"""Offline crash-boundary file images; file IO, serializer and events are doubles.

Each restart creates a new Lua runtime. Captures freeze the filesystem at an IO
boundary, before the discarded runtime's ordinary error cleanup can run.
"""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


SHARED = Path(__file__).resolve().parents[1] / 'PZSurvivorToolkit/42/media/lua/shared'
RECOVERY = 'PZSurvivorToolkitModOptionsRecovery.ini'
TARGET = 'ModOptions.ini'
OLD = 'keybind|SaucedCarts|PushCart|47\r\n\r\ntickbox|Absent|Enabled|true\r\n'
NEW = 'keybind|SaucedCarts|PushCart|18\r\n\r\ntickbox|Absent|Enabled|true\r\n'


class ModOptionsRecoveryTests(unittest.TestCase):
    def boot(self, files=None):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            files={}; writes={}; faults={}; captures={}; calls=0; logs={}
            local function copy()local result={} for k,v in pairs(files)do result[k]=v end return result end
            function getFileReader(path,create)
                if faults[path] and faults[path].read then error('injected read failure')end
                if faults[path] and faults[path].readNil then return nil end
                if files[path]==nil then if not create then return nil end;files[path]='' end
                local text=files[path]:gsub('\r\n','\n'):gsub('\r','\n')
                local lines={}
                if text~='' then
                    if text:sub(-1)~='\n' then text=text..'\n' end
                    for line in text:gmatch('(.-)\n')do lines[#lines+1]=line end
                end
                local index=0
                return {readLine=function()index=index+1;return lines[index]end,
                    close=function()if faults[path] and faults[path].readClose then error('read close failure')end end}
            end
            function cacheFileExists(path)return files[path:sub(5)]~=nil end
            function getFileWriter(path,create,append)
                writes[path]=(writes[path]or 0)+1
                local fault=faults[path]or {}
                if fault.open then return nil end
                if not append then files[path]='' end
                return {write=function(_,text)
                    if fault.write then error('injected write failure')end
                    local limit=append and fault.appendLimit or fault.limit
                    files[path]=(files[path]or '')..(limit and text:sub(1,limit)or text)
                    if fault.capture and not captures[fault.capture] and (not fault.appendOnly or append)then
                        captures[fault.capture]=copy()
                    end
                end,close=function()if fault.close then error('injected close failure')end end}
            end
            function print(text)logs[#logs+1]=text end
            nativeText=''
            PZAPI={ModOptions={OtherOptions={},save=function(self)
                calls=calls+1
                local writer=getFileWriter('ModOptions.ini',true,false)
                assert(writer);writer:write(nativeText);writer:close()
            end}}
        ''')
        for path, contents in (files or {TARGET: OLD}).items():
            lua.globals().files[path] = contents
        lua.globals().storage = lua.execute((SHARED / 'PZSurvivorToolkit/ModOptionsStorage.lua').read_text())
        lua.execute("package.preload['PZSurvivorToolkit/ModOptionsStorage']=function()return storage end")
        lua.globals().nativeText = NEW
        return lua

    def expected(self, lua):
        return lua.table_from({'keybind|SaucedCarts|PushCart|': '18'})

    def pending(self, before=OLD):
        lua = self.boot({TARGET: before})
        lua.execute("faults['ModOptions.ini']={limit=5,capture='native-partial'}")
        self.assertFalse(lua.globals().storage.save(self.expected(lua)))
        return dict(lua.globals().captures['native-partial'].items())

    def test_torn_backup_never_authorizes_target_write_and_can_retry(self):
        lua = self.boot()
        lua.globals().faults[RECOVERY] = lua.table_from({'limit': 20, 'capture': 'backup-partial'})
        self.assertFalse(lua.globals().storage.save(self.expected(lua)))
        self.assertEqual(OLD, lua.globals().files[TARGET])
        self.assertEqual(0, lua.globals().calls)
        self.assertIsNone(lua.globals().writes[TARGET])
        restarted = self.boot(dict(lua.globals().captures['backup-partial'].items()))
        self.assertTrue(restarted.globals().storage.recover())
        self.assertIsNone(restarted.globals().writes[TARGET])
        self.assertTrue(restarted.globals().storage.save(self.expected(restarted)))

    def test_native_partial_write_restores_original_on_restart_before_load(self):
        image = self.pending()
        self.assertNotEqual(OLD, image[TARGET])
        restarted = self.boot(image)
        restarted.execute((SHARED / '0000ToolkitModOptionsRecovery.lua').read_text())
        self.assertEqual(OLD, restarted.globals().files[TARGET])
        self.assertEqual(0, restarted.globals().calls)
        self.assertTrue(restarted.globals().storage.recover())

    def test_failed_native_save_rolls_back_immediately_when_io_recovers(self):
        lua = self.boot()
        lua.execute(r'''
            PZAPI.ModOptions.save=function()
                files['ModOptions.ini']='partial';error('native write failed')
            end
        ''')
        self.assertFalse(lua.globals().storage.save(self.expected(lua)))
        self.assertEqual(OLD, lua.globals().files[TARGET])
        self.assertTrue(lua.globals().storage.recover())

    def test_interrupted_rollback_keeps_before_image_for_another_process(self):
        lua = self.boot(self.pending())
        lua.globals().faults[TARGET] = lua.table_from({'limit': 9, 'capture': 'rollback-partial'})
        self.assertFalse(lua.globals().storage.recover())
        self.assertIn('SEALED|', lua.globals().files[RECOVERY])
        restarted = self.boot(dict(lua.globals().captures['rollback-partial'].items()))
        self.assertTrue(restarted.globals().storage.recover())
        self.assertEqual(OLD, restarted.globals().files[TARGET])

    def test_partial_commit_cannot_publish_consumer_marker(self):
        lua = self.boot()
        lua.globals().faults[RECOVERY] = lua.table_from({'appendLimit': 8, 'capture': 'commit-partial', 'appendOnly': True})
        self.assertFalse(lua.globals().storage.save(self.expected(lua)))
        self.assertFalse(lua.globals().storage.mark('Preset.ini', 'complete=1'))
        self.assertIsNone(lua.globals().files['Preset.ini'])
        image = dict(lua.globals().captures['commit-partial'].items())
        self.assertEqual(NEW, image[TARGET], 'capture precedes ordinary failure rollback')
        restarted = self.boot(image)
        self.assertTrue(restarted.globals().storage.recover())
        self.assertEqual(OLD, restarted.globals().files[TARGET])
        self.assertTrue(restarted.globals().storage.mark('Preset.ini', 'complete=1'))

    def test_committed_backup_leaves_later_manual_options_and_markers_intact(self):
        lua = self.boot()
        self.assertTrue(lua.globals().storage.save(self.expected(lua)))
        self.assertTrue(lua.globals().storage.mark('Preset.ini', 'complete=1'))
        image = dict(lua.globals().files.items())
        image[TARGET] = 'deliberate later native UI save\n'
        restarted = self.boot(image)
        self.assertTrue(restarted.globals().storage.recover())
        self.assertEqual(image[TARGET], restarted.globals().files[TARGET])
        self.assertIsNone(restarted.globals().writes[TARGET])
        self.assertTrue(restarted.globals().storage.matches('Preset.ini', 'complete=1'))

    def test_another_consumer_cannot_overwrite_pending_before_image(self):
        image = self.pending()
        lua = self.boot(image)
        lua.globals().faults[TARGET] = lua.table_from({'open': True})
        self.assertFalse(lua.globals().storage.save(self.expected(lua)))
        self.assertEqual(image[RECOVERY], lua.globals().files[RECOVERY])
        self.assertEqual(0, lua.globals().calls)
        self.assertIsNone(lua.globals().storage.matches('AlreadyDone.ini', 'complete=1'))
        self.assertFalse(lua.globals().storage.mark('OtherPreset.ini', 'complete=1'))
        self.assertIsNone(lua.globals().writes['OtherPreset.ini'])
        lua.globals().faults[TARGET] = None
        self.assertTrue(lua.globals().storage.save(self.expected(lua)))

    def test_bootstrap_recovers_without_cart_peek_or_events(self):
        lua = self.boot(self.pending())
        lua.execute('getActivatedMods=nil; Events=nil; PZAPI=nil')
        lua.execute((SHARED / '0000ToolkitModOptionsRecovery.lua').read_text())
        self.assertEqual(OLD, lua.globals().files[TARGET])

    def test_read_and_read_close_failures_refuse_save_and_marker(self):
        for kind in ('read', 'readClose'):
            with self.subTest(kind=kind):
                lua = self.boot(self.pending())
                lua.globals().faults[RECOVERY] = lua.table_from({kind: True})
                self.assertFalse(lua.globals().storage.recover())
                self.assertFalse(lua.globals().storage.save(self.expected(lua)))
                self.assertFalse(lua.globals().storage.mark('Preset.ini', 'complete=1'))
                self.assertEqual(0, lua.globals().calls)

    def test_empty_original_is_sealed_and_restored(self):
        lua = self.boot({TARGET: ''})
        lua.execute("nativeText='partial'; faults['ModOptions.ini']={capture='empty-before'}")
        self.assertFalse(lua.globals().storage.save(self.expected(lua)))
        restarted = self.boot(dict(lua.globals().captures['empty-before'].items()))
        self.assertTrue(restarted.globals().storage.recover())
        self.assertEqual('', restarted.globals().files[TARGET])

    def test_nil_native_reader_for_existing_file_is_not_an_empty_profile(self):
        for path in (TARGET, RECOVERY):
            with self.subTest(path=path):
                image = {TARGET: OLD, RECOVERY: 'unsealed backup'}
                lua = self.boot(image)
                lua.globals().faults[path] = lua.table_from({'readNil': True})
                self.assertFalse(lua.globals().storage.save(self.expected(lua)))
                self.assertEqual(image, dict(lua.globals().files.items()))
                self.assertEqual(0, lua.globals().calls)

    def test_late_provider_reload_failure_blocks_marker_until_retry(self):
        lua = self.boot(self.pending())
        lua.execute("PZAPI.ModOptions.load=function()error('load failed')end")
        self.assertFalse(lua.globals().storage.mark('Preset.ini', 'complete=1'))
        self.assertIsNone(lua.globals().writes['Preset.ini'])
        self.assertIsNone(lua.globals().storage.matches('Preset.ini', 'complete=1'))
        lua.execute('PZAPI.ModOptions.load=function()end')
        self.assertTrue(lua.globals().storage.mark('Preset.ini', 'complete=1'))

    def test_early_shared_legacy_reader_recovers_before_reading_mode(self):
        original = ('tickbox|organizedCategories_core|perSaveDisplayOverrides|true\r\n'
                    'tickbox|organizedCategories_core|sessionOnlyDisplayOverrides|false\r\n')
        image = self.pending(original)
        image['organizedCategories_displayOverrides.txt'] = 'T=Base.Thread=WrongGlobal\n'
        image['organizedCategories_displayOverrides_Save.One.txt'] = 'T=Base.Thread=RecoveredPerSave\n'
        lua = self.boot(image)
        lua.execute("getCore=function()return{getWorld=function()return 'Save.One'end}end")
        # Explicit require-style loading precedes even the shared bootstrap.
        lua.globals().legacy = lua.execute((SHARED / 'PZSurvivorToolkit/LegacyItemCategories.lua').read_text())
        self.assertEqual('RecoveredPerSave', lua.globals().legacy.forType('Base.Thread'))
        self.assertEqual(original, lua.globals().files[TARGET])
        self.assertTrue(lua.globals().legacy.instancesEnabled())

    def test_failed_shared_recovery_never_caches_partial_legacy_mode(self):
        original = 'tickbox|organizedCategories_core|useVanillaDefaults|true\r\n'
        lua = self.boot(self.pending(original))
        lua.globals().faults[TARGET] = lua.table_from({'open': True})
        lua.globals().legacy = lua.execute((SHARED / 'PZSurvivorToolkit/LegacyItemCategories.lua').read_text())
        self.assertFalse(lua.globals().legacy.instancesEnabled())
        self.assertFalse(lua.globals().legacy.useVanillaDefaults())
        lua.globals().faults[TARGET] = None
        self.assertTrue(lua.globals().legacy.useVanillaDefaults())
        self.assertTrue(lua.globals().legacy.instancesEnabled())

    def test_shared_server_skips_recovery_but_preserves_read_only_legacy_categories(self):
        image = self.pending()
        image[TARGET] = 'tickbox|organizedCategories_core|useVanillaDefaults|false\r\n'
        image['organizedCategories_displayOverrides.txt'] = 'T=Base.Thread=ServerLegacy\n'
        lua = self.boot(image)
        lua.execute(r'''
            isServer=function()return true end
            getFileWriter=function()error('server wrote client cache')end
            package.preload['PZSurvivorToolkit/ModOptionsStorage']=function()
                error('server required client storage')
            end
        ''')
        lua.execute((SHARED / '0000ToolkitModOptionsRecovery.lua').read_text())
        lua.globals().legacy = lua.execute((SHARED / 'PZSurvivorToolkit/LegacyItemCategories.lua').read_text())
        self.assertEqual('ServerLegacy', lua.globals().legacy.forType('Base.Thread'))
        self.assertTrue(lua.globals().legacy.instancesEnabled())
        self.assertFalse(lua.globals().legacy.useVanillaDefaults())
        self.assertEqual(image, dict(lua.globals().files.items()))
        self.assertEqual({}, dict(lua.globals().writes.items()))


if __name__ == '__main__':
    unittest.main()
