"""Locked integrations select actual source versions without broadening the test run."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import mod_integrations
from tools.queue_checks import pack


class ModIntegrations(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.game = self.root / 'game'
        self.game.mkdir()
        (self.game / 'projectzomboid.jar').write_bytes(b'game')
        (self.root / 'SurvivorQoL-selected.ini').write_text('Mods=Navigator;TVRadio_ReInvented\n')
        self.nav = self.root / 'Navigator/42.13/media/lua/client/NavigatorRadio'
        for folder, id in [('Navigator/42.13', 'Navigator'), ('TVRadio_ReInvented/common', 'TVRadio_ReInvented')]:
            path = self.root / folder
            path.mkdir(parents=True)
            (path / 'mod.info').write_text('id=' + id + '\n')
        for name in ('MonitorConfig.lua', 'MonitorRender.lua', 'NavigatorMonitorDrag.lua'):
            self.write(self.nav / name, name)
        self.tv = self.root / 'TVRadio_ReInvented/common/media/lua/client/RadioCom/RadioWindowModules/RWMMergedTV.lua'
        self.write(self.tv, 'upstream TV')
        self.write(self.tv.parent.parent / 'ISRadioWindow.lua', 'upstream window')
        self.lock = self.root / 'pack.json'

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def configure(self, integrations=(), requested=(), **overrides):
        args = SimpleNamespace(integration=list(integrations), pack_lock=self.lock, game=self.game,
                               navigator_source=None, tv_source=None,
                               native_radio_root=None, native_action_root=None, native_inventory_pane=None,
                               cleanui_inventory_pane=None,
                               mpff_source=None, bc_filter_source=None, medicine_framework_source=None)
        for key, value in overrides.items():
            setattr(args, key, value)
        requested = set(requested)
        with redirect_stdout(io.StringIO()):
            mod_integrations.configure(args, self.root, requested)
        return args, requested

    def lock_sources(self):
        pack.create(self.root, self.lock, self.game)

    def test_one_profile_selects_its_exact_checks_and_source_layer(self):
        # A later unsupported version and a common copy must not shadow the selected B42.13 source.
        self.write(self.root / 'Navigator/43/media/lua/client/NavigatorRadio/MonitorRender.lua', 'unsupported')
        self.write(self.root / 'Navigator/common/media/lua/client/NavigatorRadio/MonitorRender.lua', 'common')
        self.lock_sources()
        args, requested = self.configure(['Navigator'])
        self.assertEqual({'test_navigator.lua'}, requested)
        self.assertEqual(self.nav, args.navigator_source)
        self.assertIsNone(args.tv_source)
        self.assertIsNone(args.native_action_root)

    def test_common_only_tv_and_named_test_use_locked_sources_and_native_game(self):
        (self.tv.parent.parent / 'ISRadioWindow.lua').unlink()
        self.lock_sources()
        args, requested = self.configure(requested=['test_tv_videos.lua'])
        self.assertEqual({'test_tv_videos.lua'}, requested)
        self.assertEqual(self.tv, args.tv_source)
        self.assertIsNone(args.native_radio_root)

    def test_b42_checks_cannot_fall_back_to_legacy_root_sources(self):
        for id, source, test in (
                ('Navigator', self.nav / 'MonitorConfig.lua', 'test_navigator.lua'),
                ('TVRadio_ReInvented', self.tv, 'test_tv_videos.lua')):
            with self.subTest(id=id):
                relative = source.relative_to(self.root / id).parts[1:]
                self.write(self.root.joinpath(id, *relative), source.read_text())
                source.unlink()
                self.lock_sources()
                with self.assertRaisesRegex(ValueError, 'Missing upstream source'):
                    self.configure(requested=[test])
                self.lock.unlink()

    def test_effective_source_uses_common_fallback_and_root_only_mods(self):
        source = self.nav / 'MonitorConfig.lua'
        relative = source.relative_to(self.root / 'Navigator/42.13')
        common = self.root / 'Navigator/common' / relative
        self.write(common, 'common fallback')
        source.unlink()
        self.assertEqual(common, mod_integrations.source_path(self.root / 'Navigator', relative))
        standalone = self.root / 'Standalone' / relative
        self.write(standalone, 'root-only mod')
        self.assertEqual(standalone, mod_integrations.source_path(self.root / 'Standalone', relative))

    def test_owned_quartermaster_is_not_an_upstream_integration(self):
        self.assertNotIn('Quartermaster', mod_integrations.INTEGRATIONS)
        self.assertFalse(any(test.startswith('test_quartermaster_')
                             for spec in mod_integrations.INTEGRATIONS.values() for test in spec['tests']))

    def test_source_and_game_drift_are_rejected(self):
        self.lock_sources()
        self.write(self.nav / 'MonitorRender.lua', 'changed upstream')
        with self.assertRaisesRegex(ValueError, 'changed locked mod: Navigator'):
            self.configure(['Navigator'])
        (self.game / 'projectzomboid.jar').write_bytes(b'updated')
        with self.assertRaisesRegex(ValueError, 'Game build differs'):
            self.configure(['Navigator'])

    def test_missing_current_source_is_not_an_absent_mod_pass(self):
        (self.nav / 'MonitorRender.lua').unlink()
        self.lock_sources()
        with self.assertRaisesRegex(ValueError, 'Missing upstream source'):
            self.configure(['Navigator'])

    def test_conflicting_manual_source_and_native_root_are_rejected(self):
        self.lock_sources()
        self.configure(['Navigator'], navigator_source=self.nav)
        with self.assertRaisesRegex(ValueError, 'differs from locked'):
            self.configure(['Navigator'], navigator_source=self.root / 'other')
        with self.assertRaisesRegex(ValueError, 'differs from --game'):
            self.configure(['TVRadio_ReInvented'], native_radio_root=self.root / 'other')

    def test_layered_directory_inputs_fail_instead_of_testing_an_incomplete_tree(self):
        (self.nav / 'MonitorConfig.lua').unlink()
        self.write(self.root / 'Navigator/common/media/lua/client/NavigatorRadio/MonitorConfig.lua', 'common config')
        self.lock_sources()
        with self.assertRaisesRegex(ValueError, 'effective inputs span version/common'):
            self.configure(['Navigator'])

    def test_missing_pack_game_and_selection_are_explicit_errors(self):
        for overrides in ({'pack_lock': None}, {'game': None}):
            with self.subTest(overrides=overrides), self.assertRaisesRegex(ValueError, 'require --pack-lock and --game'):
                self.configure(['Navigator'], **overrides)
        with self.assertRaisesRegex(ValueError, 'Select --integration'):
            self.configure()

    def test_inventory_profiles_use_their_actual_version_and_only_their_checks(self):
        self.write(self.root / 'CleanUI/42.19/mod.info', 'id=CleanUI\n')
        pane = self.root / 'CleanUI/42.19/media/lua/client/ISUI/ISInventoryPane.lua'
        self.write(pane, 'CleanUI pane')
        ini = self.root / 'SurvivorQoL-selected.ini'
        ini.write_text(ini.read_text().strip() + ';CleanUI\n')
        self.lock_sources()
        cases = [('CleanUI', 'cleanui_inventory_pane', pane,
                  {'test_inventory_tags.lua', 'test_inventory_filter.lua', 'test_inventory_layout.lua',
                   'test_inventory_interaction.lua'})]
        for id, option, source, checks in cases:
            with self.subTest(id=id):
                args, requested = self.configure([id])
                self.assertEqual(source, getattr(args, option))
                self.assertEqual(checks, requested)
                if id == 'CleanUI':
                    self.assertEqual(self.game / 'media/lua/client/ISUI/ISInventoryPane.lua', args.native_inventory_pane)
                else:
                    self.assertIsNone(args.native_inventory_pane)

    def test_speed_and_container_profiles_use_exact_inputs_without_other_checks(self):
        self.write(self.root / 'MPFastForward/42/mod.info', 'id=MPFastForward\n')
        mpff = self.root / 'MPFastForward/42/media/lua'
        for name in ('shared/MPFastForward_Config.lua', 'server/MPFastForward_Server.lua'):
            self.write(mpff / name, name)
        self.write(self.root / 'BetterContainers/42.20/mod.info', 'id=EURY_CONTAINERS\n')
        filters = self.root / 'BetterContainers/42.20/media/lua/client/BetterContainers/Categorize/CategoryFilters.lua'
        self.write(filters, 'category filters')
        ini = self.root / 'SurvivorQoL-selected.ini'
        ini.write_text(ini.read_text().strip() + ';MPFastForward;EURY_CONTAINERS\n')
        self.lock_sources()
        for id, option, source, check in (
                ('MPFastForward', 'mpff_source', mpff, 'test_mpff_compat.lua'),
                ('EURY_CONTAINERS', 'bc_filter_source', filters, 'test_bc_filter_compat.lua')):
            for named in (False, True):
                with self.subTest(id=id, named=named):
                    args, requested = (self.configure(requested=[check]) if named else self.configure([id]))
                    self.assertEqual(source, getattr(args, option))
                    self.assertEqual({check}, requested)
                    for other in ('navigator_source', 'tv_source', 'native_radio_root',
                                  'native_action_root', 'native_inventory_pane', 'mpff_source', 'bc_filter_source'):
                        if other != option:
                            self.assertIsNone(getattr(args, other))

    def test_moodle_framework_selects_active_source_without_unrelated_checks(self):
        for version in ('42.13', '42.20'):
            self.write(self.root / f'MoodleFramework/{version}/mod.info', 'id=MoodleFramework\n')
            self.write(self.root / f'MoodleFramework/{version}/media/lua/client/MF_ISMoodle.lua', version)
        self.write(self.root / 'MoodleFramework/common/media/lua/client/MF_ISMoodle.lua', 'common fallback')
        source = self.root / 'MoodleFramework/42.20/media/lua/client/MF_ISMoodle.lua'
        ini = self.root / 'SurvivorQoL-selected.ini'
        ini.write_text(ini.read_text().strip() + ';MoodleFramework\n')
        self.lock_sources()
        for named in (False, True):
            with self.subTest(named=named):
                args, requested = (self.configure(requested=['test_medicine_moodles.lua']) if named
                                   else self.configure(['MoodleFramework']))
                self.assertEqual(source, args.medicine_framework_source)
                self.assertEqual({'test_medicine_moodles.lua'}, requested)
                for other in ('navigator_source', 'tv_source', 'native_radio_root',
                              'native_action_root', 'native_inventory_pane', 'cleanui_inventory_pane',
                              'mpff_source', 'bc_filter_source'):
                    self.assertIsNone(getattr(args, other), other)
                selection = {} if named else {'integrations': ['MoodleFramework']}
                if named:
                    selection['requested'] = ['test_medicine_moodles.lua']
                self.configure(**selection, medicine_framework_source=source)
                with self.assertRaisesRegex(ValueError, 'differs from locked integration inputs'):
                    self.configure(**selection, medicine_framework_source=self.root / 'other/MF_ISMoodle.lua')
