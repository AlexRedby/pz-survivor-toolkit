"""Locked integration checks consume the same effective files as Build 42."""
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
            self.write(self.root / folder / 'mod.info', 'id=' + id + '\n')
        for name in ('MonitorConfig.lua', 'MonitorRender.lua', 'NavigatorMonitorDrag.lua'):
            self.write(self.nav / name, name)
        self.tv = self.root / 'TVRadio_ReInvented/common/media/lua/client/RadioCom/RadioWindowModules/RWMMergedTV.lua'
        self.write(self.tv, 'upstream TV')
        self.write(self.tv.parent.parent / 'ISRadioWindow.lua', 'upstream window')
        self.lock = self.root / 'pack.json'

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def select(self, identifier, folder):
        self.write(self.root / folder / 'mod.info', 'id=' + identifier + '\n')
        ini = self.root / 'SurvivorQoL-selected.ini'
        ini.write_text(ini.read_text().strip() + ';' + identifier + '\n')

    def cleanui(self, full=False):
        self.select('CleanUI', 'CleanUI/42.19')
        root = self.root / 'CleanUI/42.19/media/lua/client'
        self.write(root / 'ISUI/ISInventoryPane.lua', 'CleanUI pane')
        if full:
            for relative, text in (
                    ('ISUI/ISInventoryPage.lua', 'CleanUI page'),
                    ('CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPane.lua', 'CleanUI vanilla pane'),
                    ('CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPage.lua', 'CleanUI vanilla page')):
                self.write(root / relative, text)
        return root

    def containers(self, full=False):
        self.select('EURY_CONTAINERS', 'BetterContainers/42.20')
        root = self.root / 'BetterContainers/42.20/media/lua/client/BetterContainers'
        self.write(root / 'Categorize/CategoryFilters.lua', 'category filters')
        if full:
            self.write(root / 'Proximity/Proximity_SmartDeposit.lua', 'BC smart deposit')
            self.write(root / 'Customize/Customize_ISInventoryPage.lua', 'BC page customizer')
        return root

    def configure(self, integrations=(), requested=(), **overrides):
        args = SimpleNamespace(integration=list(integrations), pack_lock=self.lock, game=self.game,
                               navigator_source=None, tv_source=None,
                               native_radio_root=None, native_action_root=None, native_inventory_pane=None,
                               cleanui_inventory_pane=None, mpff_source=None, bc_filter_source=None,
                               medicine_framework_source=None)
        for key, value in overrides.items():
            setattr(args, key, value)
        requested = set(requested)
        with redirect_stdout(io.StringIO()):
            mod_integrations.configure(args, self.root, requested)
        return args, requested

    def bound(self, args, test):
        values = {}
        mod_integrations.bind_sources(SimpleNamespace(globals=lambda: values), test, args)
        return values

    def lock_sources(self):
        pack.create(self.root, self.lock, self.game)

    def test_one_profile_selects_its_exact_checks_and_source_layer(self):
        self.write(self.root / 'Navigator/43/media/lua/client/NavigatorRadio/MonitorRender.lua', 'unsupported')
        self.write(self.root / 'Navigator/common/media/lua/client/NavigatorRadio/MonitorRender.lua', 'common')
        self.lock_sources()
        args, requested = self.configure(['Navigator'])
        self.assertEqual({'test_navigator.lua'}, requested)
        self.assertEqual({'NativeNavigatorConfig': 'MonitorConfig.lua',
                          'NativeNavigatorRender': 'MonitorRender.lua',
                          'NativeNavigatorDrag': 'NavigatorMonitorDrag.lua'}, self.bound(args, 'test_navigator.lua'))
        self.assertEqual(self.nav / 'MonitorRender.lua', args.integration_sources['test_navigator.lua']['NativeNavigatorRender'])
        self.assertIsNone(args.native_action_root)
        self.assertEqual({}, self.bound(args, 'test_tv_videos.lua'))

    def test_common_only_tv_named_check_does_not_require_window_or_native_radio(self):
        (self.tv.parent.parent / 'ISRadioWindow.lua').unlink()
        self.lock_sources()
        args, requested = self.configure(requested=['test_tv_videos.lua'])
        self.assertEqual({'test_tv_videos.lua'}, requested)
        self.assertEqual({'TVSource': 'upstream TV'}, self.bound(args, 'test_tv_videos.lua'))
        self.assertEqual(self.tv, args.integration_sources['test_tv_videos.lua']['TVSource'])
        self.assertIsNone(args.native_radio_root)

    def test_b42_checks_cannot_fall_back_to_legacy_root_sources(self):
        for identifier, source, test in (
                ('Navigator', self.nav / 'MonitorConfig.lua', 'test_navigator.lua'),
                ('TVRadio_ReInvented', self.tv, 'test_tv_videos.lua')):
            with self.subTest(id=identifier):
                relative = source.relative_to(self.root / identifier).parts[1:]
                self.write(self.root.joinpath(identifier, *relative), source.read_text())
                source.unlink()
                self.lock_sources()
                with self.assertRaisesRegex(ValueError, 'Missing upstream source'):
                    self.configure(requested=[test])
                self.lock.unlink()

    def test_effective_source_uses_common_fallback_and_rejects_root_only_mods(self):
        source = self.nav / 'MonitorConfig.lua'
        relative = source.relative_to(self.root / 'Navigator/42.13')
        common = self.root / 'Navigator/common' / relative
        self.write(common, 'common fallback')
        source.unlink()
        self.assertEqual(common, mod_integrations.source_path(self.root / 'Navigator', relative))
        self.write(self.root / 'Standalone' / relative, 'root-only mod')
        with self.assertRaisesRegex(ValueError, 'Missing upstream source'):
            mod_integrations.source_path(self.root / 'Standalone', relative)

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

    def test_layered_required_inputs_bind_every_effective_file(self):
        (self.nav / 'MonitorConfig.lua').unlink()
        common = self.write(self.root / 'Navigator/common/media/lua/client/NavigatorRadio/MonitorConfig.lua', 'common config')
        self.lock_sources()
        args, requested = self.configure(['Navigator'])
        self.assertEqual({'test_navigator.lua'}, requested)
        self.assertEqual(common, args.integration_sources['test_navigator.lua']['NativeNavigatorConfig'])
        self.assertEqual({'NativeNavigatorConfig': 'common config', 'NativeNavigatorRender': 'MonitorRender.lua',
                          'NativeNavigatorDrag': 'NavigatorMonitorDrag.lua'}, self.bound(args, 'test_navigator.lua'))
        # A directory override cannot describe this effective mixed-layer tree.
        with self.assertRaisesRegex(ValueError, 'differs from locked'):
            self.configure(['Navigator'], navigator_source=self.nav)

    def test_missing_pack_game_and_selection_are_explicit_errors(self):
        for overrides in ({'pack_lock': None}, {'game': None}):
            with self.subTest(overrides=overrides), self.assertRaisesRegex(ValueError, 'require --pack-lock and --game'):
                self.configure(['Navigator'], **overrides)
        with self.assertRaisesRegex(ValueError, 'Select --integration'):
            self.configure()

    def test_full_cleanui_profile_includes_transfer_and_page_consumers(self):
        clean = self.cleanui(full=True)
        self.containers(full=True)
        self.lock_sources()
        args, requested = self.configure(['CleanUI'])
        self.assertEqual({'test_inventory_tags.lua', 'test_inventory_filter.lua', 'test_inventory_search.lua',
                          'test_inventory_layout.lua', 'test_inventory_interaction.lua',
                          'test_inventory_transfer_operations.lua', 'test_container_configuration_menus.lua',
                          'test_smart_deposit.lua'}, requested)
        self.assertEqual({'CleanUIInventoryPaneSource': 'CleanUI pane',
                          'CleanUIVanillaInventoryPaneSource': 'CleanUI vanilla pane'},
                         self.bound(args, 'test_inventory_transfer_operations.lua'))
        page = self.bound(args, 'test_container_configuration_menus.lua')
        self.assertEqual('CleanUI page', page['CleanUIInventoryPageSource'])
        self.assertEqual('CleanUI vanilla page', page['CleanUIVanillaInventoryPageSource'])
        self.assertEqual('BC page customizer', page['NativeBCPageCustomizerSource'])
        self.assertEqual(clean / 'ISUI/ISInventoryPane.lua',
                         args.integration_sources['test_inventory_filter.lua']['CleanUIInventoryPaneSource'])
        self.assertEqual(self.game / 'media/lua', args.native_action_root)
        self.assertEqual(self.game / 'media/lua/client/ISUI/ISInventoryPane.lua', args.native_inventory_pane)

    def test_named_pane_check_does_not_require_unrelated_cleanui_files(self):
        self.cleanui()
        self.lock_sources()
        args, requested = self.configure(requested=['test_inventory_filter.lua'])
        self.assertEqual({'test_inventory_filter.lua'}, requested)
        self.assertEqual({'CleanUIInventoryPaneSource': 'CleanUI pane'}, self.bound(args, 'test_inventory_filter.lua'))
        self.assertIsNone(args.native_action_root)

    def test_common_pane_does_not_select_stale_common_handler(self):
        root = self.cleanui()
        pane = root / 'ISUI/ISInventoryPane.lua'
        common = self.root / 'CleanUI/common/media/lua/client/ISUI'
        self.write(common / pane.name, pane.read_text())
        pane.unlink()
        self.write(common / 'ISInventoryPageTransferHandler.lua', 'stale common handler')
        current = self.write(root / 'ISUI/ISInventoryPageTransferHandler.lua', 'selected handler')
        self.lock_sources()
        args, _ = self.configure(requested=['test_inventory_filter.lua'])
        self.assertEqual(current, args.integration_sources['test_inventory_filter.lua']['CleanUIInventoryTransferHandlerSource'])
        self.assertEqual({'CleanUIInventoryPaneSource': 'CleanUI pane',
                          'CleanUIInventoryTransferHandlerSource': 'selected handler'},
                         self.bound(args, 'test_inventory_filter.lua'))
        with self.assertRaisesRegex(ValueError, 'differs from locked'):
            self.configure(requested=['test_inventory_filter.lua'], cleanui_inventory_pane=common / pane.name)

    def test_selected_pane_keeps_common_only_handler(self):
        self.cleanui()
        self.write(self.root / 'CleanUI/common/media/lua/client/ISUI/ISInventoryPageTransferHandler.lua', 'common handler')
        self.lock_sources()
        args, _ = self.configure(requested=['test_inventory_filter.lua'])
        self.assertEqual({'CleanUIInventoryPaneSource': 'CleanUI pane',
                          'CleanUIInventoryTransferHandlerSource': 'common handler'},
                         self.bound(args, 'test_inventory_filter.lua'))

    def test_cleanui_native_input_override_must_match_locked_game(self):
        clean = self.cleanui(full=True)
        self.containers(full=True)
        self.lock_sources()
        cases = [('test_inventory_filter.lua', 'native_inventory_pane',
                  self.game / 'media/lua/client/ISUI/ISInventoryPane.lua'),
                 ('test_inventory_transfer_operations.lua', 'native_action_root', self.game / 'media/lua'),
                 ('test_container_configuration_menus.lua', 'native_action_root', self.game / 'media/lua')]
        for test, option, path in cases:
            with self.subTest(test=test):
                self.configure(requested=[test], **{option: path})
                with self.assertRaisesRegex(ValueError, 'differs from --game'):
                    self.configure(requested=[test], **{option: self.root / 'other'})
        self.configure(requested=['test_inventory_filter.lua'], cleanui_inventory_pane=clean / 'ISUI/ISInventoryPane.lua')

    def test_full_container_profile_binds_smart_deposit_and_customizer(self):
        self.cleanui(full=True)
        self.containers(full=True)
        self.lock_sources()
        args, requested = self.configure(['EURY_CONTAINERS'])
        self.assertEqual({'test_bc_filter_compat.lua', 'test_smart_deposit.lua', 'test_container_configuration_menus.lua'}, requested)
        self.assertEqual({'NativeBCFilterSource': 'category filters'}, self.bound(args, 'test_bc_filter_compat.lua'))
        smart = self.bound(args, 'test_smart_deposit.lua')
        self.assertEqual('BC smart deposit', smart['NativeBCSmartDepositSource'])
        self.assertEqual('CleanUI page', smart['CleanUIInventoryPageSource'])
        self.assertEqual('BC page customizer',
                         self.bound(args, 'test_container_configuration_menus.lua')['NativeBCPageCustomizerSource'])
        self.assertIsNone(args.native_inventory_pane)

    def test_named_container_filter_does_not_require_unrelated_sources(self):
        self.containers()
        self.lock_sources()
        args, requested = self.configure(requested=['test_bc_filter_compat.lua'])
        self.assertEqual({'test_bc_filter_compat.lua'}, requested)
        self.assertEqual({'NativeBCFilterSource': 'category filters'}, self.bound(args, 'test_bc_filter_compat.lua'))
        self.assertIsNone(args.native_action_root)

    def test_speed_profile_binds_exact_sources_without_other_checks(self):
        self.select('MPFastForward', 'MPFastForward/42')
        mpff = self.root / 'MPFastForward/42/media/lua'
        for name in ('shared/MPFastForward_Config.lua', 'server/MPFastForward_Server.lua'):
            self.write(mpff / name, name)
        self.lock_sources()
        for named in (False, True):
            with self.subTest(named=named):
                args, requested = (self.configure(requested=['test_mpff_compat.lua']) if named
                                   else self.configure(['MPFastForward']))
                self.assertEqual({'test_mpff_compat.lua'}, requested)
                self.assertEqual({'NativeMPFFConfigSource': 'shared/MPFastForward_Config.lua',
                                  'NativeMPFFServerSource': 'server/MPFastForward_Server.lua'},
                                 self.bound(args, 'test_mpff_compat.lua'))
                self.assertIsNone(args.native_action_root)

    def test_moodle_framework_selects_active_source_without_unrelated_checks(self):
        self.select('MoodleFramework', 'MoodleFramework/42.13')
        for version in ('42.13', '42.20'):
            self.write(self.root / f'MoodleFramework/{version}/mod.info', 'id=MoodleFramework\n')
            self.write(self.root / f'MoodleFramework/{version}/media/lua/client/MF_ISMoodle.lua', version)
        self.write(self.root / 'MoodleFramework/common/media/lua/client/MF_ISMoodle.lua', 'common fallback')
        source = self.root / 'MoodleFramework/42.20/media/lua/client/MF_ISMoodle.lua'
        self.lock_sources()
        for named in (False, True):
            with self.subTest(named=named):
                selection = {'requested': ['test_medicine_moodles.lua']} if named else {'integrations': ['MoodleFramework']}
                args, requested = self.configure(**selection)
                self.assertEqual(source, args.integration_sources['test_medicine_moodles.lua']['NativeMedicineFrameworkSource'])
                self.assertEqual({'NativeMedicineFrameworkSource': '42.20'}, self.bound(args, 'test_medicine_moodles.lua'))
                self.assertEqual({'test_medicine_moodles.lua'}, requested)
                self.assertIsNone(args.native_action_root)
                self.assertIsNone(args.native_inventory_pane)
                self.configure(**selection, medicine_framework_source=source)
                with self.assertRaisesRegex(ValueError, 'differs from locked integration inputs'):
                    self.configure(**selection, medicine_framework_source=self.root / 'other/MF_ISMoodle.lua')
