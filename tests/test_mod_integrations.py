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
        (self.root / 'SurvivorQoL-selected.ini').write_text('Mods=Navigator;TVRadio_ReInvented;Quartermaster\n')
        self.nav = self.root / 'Navigator/42.13/media/lua/client/NavigatorRadio'
        for folder, id in [('Navigator/42.13', 'Navigator'), ('TVRadio_ReInvented/common', 'TVRadio_ReInvented'),
                           ('Quartermaster/42', 'Quartermaster')]:
            path = self.root / folder
            path.mkdir(parents=True)
            (path / 'mod.info').write_text('id=' + id + '\n')
        for name in ('MonitorConfig.lua', 'MonitorRender.lua', 'NavigatorMonitorDrag.lua'):
            self.write(self.nav / name, name)
        self.tv = self.root / 'TVRadio_ReInvented/common/media/lua/client/RadioCom/RadioWindowModules/RWMMergedTV.lua'
        self.write(self.tv, 'upstream TV')
        self.write(self.tv.parent.parent / 'ISRadioWindow.lua', 'upstream window')
        self.qm = self.root / 'Quartermaster/42/media/lua'
        for name in ('client/LootSorter_Picker.lua', 'client/LootSorter_Core.lua', 'client/LootSorter_CraftMenu.lua',
                     'shared/LootSorter_Debug.lua', 'shared/LootSorter_Plan.lua', 'shared/LootSorter_Presets.lua',
                     'shared/LootSorter_Util.lua'):
            self.write(self.qm / name, name)
        self.lock = self.root / 'pack.json'

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def configure(self, integrations=(), requested=(), **overrides):
        args = SimpleNamespace(integration=list(integrations), pack_lock=self.lock, game=self.game,
                               navigator_source=None, tv_source=None, quartermaster_source=None,
                               native_radio_root=None, native_action_root=None)
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

    def test_named_quartermaster_routing_does_not_require_ui_inputs(self):
        (self.qm / 'client/LootSorter_Picker.lua').unlink()
        (self.qm / 'client/LootSorter_CraftMenu.lua').unlink()
        self.lock_sources()
        args, requested = self.configure(requested=['test_quartermaster_item_routing.lua'])
        self.assertEqual({'test_quartermaster_item_routing.lua'}, requested)
        self.assertEqual(self.qm, args.quartermaster_source)
        self.assertIsNone(args.native_action_root)

    def test_quartermaster_profile_includes_native_picker_and_preserves_explicit_tests(self):
        self.lock_sources()
        args, requested = self.configure(['Quartermaster'], ['test_ui_style.lua'])
        self.assertEqual(self.qm, args.quartermaster_source)
        self.assertEqual(self.game / 'media/lua', args.native_action_root)
        self.assertEqual({'test_ui_style.lua', 'test_quartermaster_tags.lua', 'test_quartermaster_tag_rules.lua',
                          'test_quartermaster_item_routing.lua', 'test_quartermaster_craft_ui.lua'}, requested)

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
            self.configure(['Quartermaster'], native_action_root=self.root / 'other')

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

    def test_absent_integration_cannot_pass_only_the_absent_mod_guard(self):
        (self.root / 'SurvivorQoL-selected.ini').write_text('Mods=Navigator;TVRadio_ReInvented\n')
        self.lock_sources()
        with self.assertRaisesRegex(ValueError, 'absent from the locked pack: Quartermaster'):
            self.configure(['Quartermaster'])
