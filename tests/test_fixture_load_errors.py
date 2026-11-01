"""Stop only on completed native loader failures attributed to staged fixtures."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.fixture_errors import FixtureLoadMonitor


HEADER = 'Oct 29, 2026 4:52:47 PM zombie.Lua.LuaManager RunLuaInternal\n'
NORMAL = 'LOG  : Lua          f:0> next native record\n'


class FixtureLoadErrorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.runtime = {'game': str(self.root / 'game'), 'fixture': {'mods': ['GeneratedFixture']},
                        'roles': {'client1': {'cache': str(self.root / 'client1')},
                                  'server': {'cache': str(self.root / 'server')}}}
        self.selection = {'kind': 'mp', 'mods': ['ForeignMod', 'PZSurvivorToolkit']}
        self.source = self.stage('client1', 'GeneratedFixture', 'client/ZZFixture.lua')
        self.stage('client1', 'ActionQueueTest', 'shared/QueueTest.lua')
        self.foreign = self.stage('client1', 'ForeignMod', 'client/Foreign.lua')
        self.toolkit = self.stage('client1', 'PZSurvivorToolkit', 'client/Toolkit.lua')
        self.server_source = self.stage('server', 'GeneratedFixture', 'server/ZZServerFixture.lua')
        self.seal_game()

    def stage(self, role, identifier, relative, layer='42'):
        base = self.root / role / 'mods' / identifier / layer
        base.mkdir(parents=True, exist_ok=True)
        (base / 'mod.info').write_text('name=Display ' + identifier + '\nid=' + identifier + '\n')
        path = base / 'media/lua' / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('local fixture = true\n')
        return path

    def seal_game(self, names=()):
        (self.root / 'game-inputs.json').write_text(json.dumps({
            'game': self.runtime['game'], 'trees': {'media/lua': {name: '0' * 64 for name in names},
                                                  'media/scripts': {}}}))

    def monitor(self):
        return FixtureLoadMonitor(self.root, self.runtime, self.selection)

    def compile(self, path=None, closed=True):
        path = self.source if path is None else path
        return (HEADER + 'SEVERE: Error found in LUA file: ' + str(path) + '\n'
                + 'ERROR: General f:0> LuaManager.RunLuaInternal> Exception thrown\n'
                + '\tse.krka.kahlua.vm.KahluaException: ZZFixture.lua:556: function has more than 60 upvalues\n'
                + '\tStack trace:\n\t\tLua.ZZFixture.lua(ZZFixture.lua:556)\n'
                + '\t\tzombie.Lua.LuaManager.RunLuaInternal(LuaManager.java:1372)\n'
                + (NORMAL if closed else ''))

    def runtime_error(self, source='ZZFixture.lua', closed=True, trace_prefix='SEVERE: '):
        return (HEADER + 'SEVERE: attempt to index a nil value\n'
                + HEADER + 'SEVERE: se.krka.kahlua.vm.KahluaException: attempt to index a nil value\n'
                + HEADER + trace_prefix + 'at ' + source + ':12\n'
                + 'at QueueTest.lua:4\n' + (NORMAL if closed else ''))

    def assert_finding(self, value, kind, role='client1'):
        self.assertIsNotNone(value)
        self.assertEqual(value['role'], role)
        self.assertEqual(value['kind'], kind)
        self.assertGreaterEqual(value['line'], 1)
        self.assertTrue(value['message'])
        self.assertTrue(value['block'])
        self.assertFalse(Path(value['file']).is_absolute())

    def test_native_compiler_failure_uses_exact_generated_fixture_path(self):
        self.assert_finding(self.monitor().find('client1', self.compile()), 'compile')

    def test_completed_runtime_failure_uses_first_lua_frame(self):
        self.assert_finding(self.monitor().find('client1', self.runtime_error()), 'runtime')

    def test_source_suffix_is_independent_of_jul_timestamp_format(self):
        value = self.runtime_error().replace('Oct 29, 2026 4:52:47 PM', '29 oct. 2026 16:52:47')
        self.assert_finding(self.monitor().find('client1', value), 'runtime')

    def test_plain_trace_continuation_is_a_runtime_frame(self):
        self.assert_finding(self.monitor().find('client1', self.runtime_error(trace_prefix=' ')), 'runtime')

    def test_common_action_queue_fixture_is_owned_without_extra_mod_id(self):
        self.assert_finding(self.monitor().find('client1', self.runtime_error('QueueTest.lua')), 'runtime')

    def test_foreign_mod_and_toolkit_are_outside_fixture_scope(self):
        for path in (self.foreign, self.toolkit):
            with self.subTest(path=path.name):
                self.assertIsNone(self.monitor().find('client1', self.compile(path)))
                self.assertIsNone(self.monitor().find('client1', self.runtime_error(path.name)))

    def test_foreign_first_frame_cannot_borrow_a_later_fixture_frame(self):
        value = self.runtime_error('Foreign.lua').replace('at QueueTest.lua:4', 'at ZZFixture.lua:4')
        self.assertIsNone(self.monitor().find('client1', value))

    def test_adjacent_loader_failures_do_not_hide_or_borrow_fixture_scope(self):
        monitor = self.monitor()
        foreign = self.runtime_error('Foreign.lua', closed=False)
        self.assert_finding(monitor.find('client1', foreign + self.runtime_error()), 'runtime')
        self.assert_finding(monitor.find('client1', self.runtime_error(closed=False) + foreign), 'runtime')
        self.assert_finding(monitor.find('client1', self.compile(self.foreign, closed=False)
                                        + self.runtime_error()), 'runtime')

    def test_error_text_cannot_override_the_final_jul_stack_source(self):
        text = self.runtime_error('Foreign.lua').replace('attempt to index a nil value',
                                                        'failed while reading ZZFixture.lua:12')
        self.assertIsNone(self.monitor().find('client1', text))

    def test_full_path_does_not_match_a_foreign_substring_or_suffix(self):
        for path in (str(self.source) + '.other', str(self.source).replace('/GeneratedFixture/', '/OtherGeneratedFixture/'),
                     self.source.name):
            with self.subTest(path=path):
                self.assertIsNone(self.monitor().find('client1', self.compile(path)))

    def test_windows_separators_preserve_exact_staged_path_identity(self):
        value = self.compile(str(self.source).replace('/', '\\'))
        self.assert_finding(self.monitor().find('client1', value), 'compile')

    def test_localized_jul_levels_keep_compile_and_runtime_failures(self):
        self.assert_finding(self.monitor().find('client1', self.compile().replace('SEVERE:', 'ОШИБКА:')), 'compile')
        self.assert_finding(self.monitor().find('client1', self.runtime_error().replace('SEVERE:', 'GRAVE:')), 'runtime')

    def test_lua_log_payload_cannot_impersonate_loader_source_header(self):
        value = self.runtime_error().replace(HEADER, 'LOG : Lua > ' + HEADER)
        self.assertIsNone(self.monitor().find('client1', value))

    def test_incomplete_runtime_cluster_at_eof_is_not_a_failure(self):
        self.assertIsNone(self.monitor().find('client1', self.runtime_error(closed=False)))

    def test_incomplete_compile_cluster_at_eof_is_not_a_failure(self):
        self.assertIsNone(self.monitor().find('client1', self.compile(closed=False)))

    def test_partial_writes_complete_only_after_the_next_record_newline(self):
        monitor = self.monitor()
        text = self.runtime_error(closed=False)
        for suffix in ('', 'LOG', 'LOG : Lua > next record'):
            with self.subTest(suffix=suffix):
                self.assertIsNone(monitor.find('client1', text + suffix))
        self.assert_finding(monitor.find('client1', text + NORMAL), 'runtime')

    def test_other_jul_record_closes_runtime_cluster(self):
        value = self.runtime_error(closed=False) + 'Oct 29, 2026 4:52:48 PM zombie.iso.IsoCell PlaceLot\n'
        value += 'SEVERE: Missing tile definition: unrelated\n'
        self.assert_finding(self.monitor().find('client1', value), 'runtime')

    def test_unrelated_jul_source_cannot_claim_a_fixture_frame(self):
        value = self.runtime_error().replace('zombie.Lua.LuaManager RunLuaInternal', 'zombie.iso.IsoCell PlaceLot')
        self.assertIsNone(self.monitor().find('client1', value))

    def test_require_warning_and_foreign_error_do_not_open_loader_cluster(self):
        value = ('WARN : Lua f:0 at Lua((MOD:Display GeneratedFixture)).ZZFixture.lua> require("Missing") failed\n'
                 'ERROR: General f:0> unrelated native exception\n'
                 '\tat ZZFixture.lua:12\n' + NORMAL)
        self.assertIsNone(self.monitor().find('client1', value))

    def test_caught_exception_with_loader_stack_is_nonfatal_without_failed_pcall_jul(self):
        value = ('ERROR: General f:0> Lua((MOD:Display GeneratedFixture)).guarded> Exception thrown\n'
                 '\tse.krka.kahlua.vm.KahluaException: expected caught error\n'
                 '\tStack trace:\n'
                 '\t\tLua((MOD:Display GeneratedFixture)).guarded(ZZFixture.lua:12)\n'
                 '\t\tzombie.Lua.LuaManager.RunLuaInternal(LuaManager.java:1402)\n'
                 '\t\tzombie.Lua.LuaManager.LoadDirBase(LuaManager.java:1225)\n'
                 'ERROR: General f:0> KahluaThread.flushErrorMessage> dumping Lua stack trace\n'
                 '-----------------------------------------\nSTACK TRACE\n-----------------------------------------\n'
                 '\tLua((MOD:Display GeneratedFixture)).guarded(ZZFixture.lua:12)\n' + NORMAL)
        self.assertIsNone(self.monitor().find('client1', value))

    def test_fixture_frame_after_closed_unrelated_cluster_is_not_borrowed(self):
        value = HEADER + 'SEVERE: unrelated error\n' + NORMAL + 'at ZZFixture.lua:12\n' + NORMAL
        self.assertIsNone(self.monitor().find('client1', value))

    def test_duplicate_basename_in_active_foreign_mod_is_ambiguous(self):
        self.stage('client1', 'ForeignMod', 'shared/ZZFixture.lua')
        self.assertIsNone(self.monitor().find('client1', self.runtime_error()))
        self.assert_finding(self.monitor().find('client1', self.compile()), 'compile')

    def test_sealed_vanilla_basename_collision_is_ambiguous(self):
        self.seal_game(['client/ZZFixture.lua'])
        self.assertIsNone(self.monitor().find('client1', self.runtime_error()))

    def test_shadowed_common_source_does_not_duplicate_effective_version_source(self):
        common = self.stage('client1', 'GeneratedFixture', 'client/ZZFixture.lua', layer='common')
        self.assert_finding(self.monitor().find('client1', self.runtime_error()), 'runtime')
        self.assertIsNone(self.monitor().find('client1', self.compile(common)))

    def test_unselected_version_and_legacy_sources_are_not_active(self):
        for layer in ('41', '43'):
            path = self.stage('client1', 'GeneratedFixture', 'client/InactiveFixture.lua', layer=layer)
            self.assertIsNone(self.monitor().find('client1', self.compile(path)))
        legacy = self.root / 'client1/mods/GeneratedFixture/media/lua/client/LegacyFixture.lua'
        legacy.parent.mkdir(parents=True)
        legacy.write_text('local legacy = true\n')
        self.assertIsNone(self.monitor().find('client1', self.compile(legacy)))
        self.assertIsNone(self.monitor().find('client1', self.runtime_error('InactiveFixture.lua')))

    def test_dedicated_server_uses_its_own_cache(self):
        self.assert_finding(self.monitor().find('server', self.compile(self.server_source)), 'compile', role='server')
        self.assertIsNone(self.monitor().find('server', self.compile(self.source)))

    def test_host_server_uses_owner_cache(self):
        self.runtime['host_cache'] = self.runtime['roles']['client1']['cache']
        self.selection['options'] = {'mp_host': True}
        self.assert_finding(self.monitor().find('server', self.compile(self.source)), 'compile', role='server')
        self.assert_finding(self.monitor().find('server', self.runtime_error()), 'runtime', role='server')
        self.assertIsNone(self.monitor().find('server', self.compile(self.server_source)))

    def test_check_finds_failure_after_an_unrelated_role_log(self):
        finding = self.monitor().check({'server': NORMAL, 'client1': self.runtime_error()})
        self.assert_finding(finding, 'runtime')


if __name__ == '__main__':
    unittest.main()
