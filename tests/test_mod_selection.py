"""Build 42 source selection follows the game's numeric branch and overlay rules."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import mod_integrations
from tools.queue_checks import mod_selection


class ModSelection(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def write(self, relative, text='content'):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_future_only_branch_keeps_common_content_and_metadata(self):
        common = self.write('common/media/lua/shared/Feature.lua')
        info = self.write('common/mod.info', 'id=CommonMod\n')
        self.write('42.22/media/lua/shared/Feature.lua', 'future')
        self.write('42.22/mod.info', 'id=FutureMod\n')

        self.assertEqual(self.root / '42.0', mod_selection.selected_mod_version(self.root))
        self.assertEqual([self.root / 'common'], mod_selection.mod_layers(self.root))
        self.assertEqual(info, mod_selection.mod_info(self.root))
        self.assertEqual(common, mod_integrations.source_path(self.root, 'media/lua/shared/Feature.lua'))

    def test_patch_components_do_not_make_current_branch_incompatible(self):
        self.write('42.20/mod.info', 'id=Older\n')
        info = self.write('42.21.0/mod.info', 'id=Current\n')
        self.write('42.22/mod.info', 'id=Future\n')

        self.assertEqual(self.root / '42.21.0', mod_selection.selected_mod_version(self.root))
        self.assertEqual([self.root / '42.21.0'], mod_selection.mod_layers(self.root))
        self.assertEqual(info, mod_selection.mod_info(self.root))

    def test_selected_branch_overlays_common_and_supplies_metadata_first(self):
        relative = 'media/lua/shared/Feature.lua'
        self.write('common/' + relative, 'common')
        selected = self.write('42.21/' + relative, 'selected')
        common_only = self.write('common/media/lua/shared/CommonOnly.lua')
        common_info = self.write('common/mod.info', 'id=Common\n')
        selected_info = self.write('42.21/mod.info', 'id=Selected\n')
        self.write('mod.info', 'id=Legacy\n')
        self.write('42.20/' + relative, 'older')

        self.assertEqual([self.root / 'common', self.root / '42.21'], mod_selection.mod_layers(self.root))
        self.assertEqual(selected, mod_integrations.source_path(self.root, relative))
        self.assertEqual(common_only, mod_integrations.source_path(self.root, 'media/lua/shared/CommonOnly.lua'))
        self.assertEqual(selected_info, mod_selection.mod_info(self.root))
        selected_info.unlink()
        self.assertEqual(common_info, mod_selection.mod_info(self.root))
        common_info.unlink()
        self.assertIsNone(mod_selection.mod_info(self.root))

    def test_missing_default_branch_never_activates_legacy_root(self):
        self.write('mod.info', 'id=Legacy\n')
        self.write('media/lua/shared/Feature.lua', 'legacy')

        self.assertEqual(self.root / '42.0', mod_selection.selected_mod_version(self.root))
        self.assertEqual([], mod_selection.mod_layers(self.root))
        self.assertIsNone(mod_selection.mod_info(self.root))
        with self.assertRaisesRegex(ValueError, 'Missing upstream source'):
            mod_integrations.source_path(self.root, 'media/lua/shared/Feature.lua')

    def test_default_branch_is_available_without_numeric_compatible_directory(self):
        self.write('43/mod.info', 'id=Future\n')
        self.assertEqual(self.root / '42.0', mod_selection.selected_mod_version(self.root))
        self.assertEqual([], mod_selection.mod_layers(self.root))

    def test_numeric_minor_order_does_not_use_lexicographic_names(self):
        self.write('42.9/mod.info', 'id=Nine\n')
        self.write('42.20/mod.info', 'id=Twenty\n')
        self.assertEqual(self.root / '42.20', mod_selection.selected_mod_version(self.root))

    def test_equal_numeric_aliases_follow_directory_enumeration_order(self):
        first = self.write('42.21.0/mod.info').parent
        last = self.write('42.21/mod.info').parent
        with patch.object(Path, 'iterdir', return_value=[first, last]):
            self.assertEqual(last, mod_selection.selected_mod_version(self.root))
        with patch.object(Path, 'iterdir', return_value=[last, first]):
            self.assertEqual(first, mod_selection.selected_mod_version(self.root))

    def test_minor_is_clamped_to_999_before_comparing_numeric_aliases(self):
        first = self.write('42.1000/mod.info').parent
        last = self.write('42.999/mod.info').parent
        with patch.object(Path, 'iterdir', return_value=[first, last]):
            self.assertEqual(last, mod_selection.selected_mod_version(self.root, version=(42, 999)))


if __name__ == '__main__':
    unittest.main()
