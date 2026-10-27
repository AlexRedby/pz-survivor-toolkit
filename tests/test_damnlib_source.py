"""Remove only the reviewed active recipe pair from a complete dependency copy."""

import hashlib
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from tools import damnlib_source, dependency_source


PREFIX = b"module Base\r\n{\r\n    craftRecipe KeepBefore { inputs { item 1 Base.Nails, } }\r\n\r\n"
PAIR = (b"    craftRecipe damnCraftRemoveBatteryFromPlasticWeldingGun\r\n"
        b"    { inputs { item 1 [damnCraft.PlasticWeldingGun] mode:keep, } }\r\n\r\n"
        b"    craftRecipe damnCraftInsertBatteryIntoPlasticWeldingGun\r\n"
        b"    { inputs { item 1 [Base.Battery] mode:destroy, } }\r\n\r\n")
SUFFIX = (b"    /************************ Rubber Mounts ************************/\r\n"
          b"    craftRecipe KeepAfter { outputs { item 1 Base.Nails, } }\r\n}\r\n")
ORIGINAL, EXPECTED = PREFIX + PAIR + SUFFIX, PREFIX + SUFFIX


def digest(value):
    return hashlib.sha256(value).hexdigest()


def files(root):
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob('*') if p.is_file()}


class DAMNLibrarySource(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.source, self.output = self.root / 'source', self.root / 'prepared'
        self.relative = Path('42.20') / damnlib_source.TARGET
        self.target = self.source / self.relative
        self.target.parent.mkdir(parents=True); self.target.write_bytes(ORIGINAL)
        (self.source / '42.20/mod.info').write_text('id=damnlib\nmodversion=fixture\n')
        for layer in ('common', '42.0', '42.30'):
            (self.source / layer).mkdir()
            (self.source / layer / 'unchanged.bin').write_bytes(b'\x00all other assets\xff\r\n')
        self.addCleanup(patch.stopall)
        patch.object(damnlib_source, 'ORIGINAL_SOURCE_SHA256', digest(ORIGINAL)).start()
        patch.object(damnlib_source, 'PATCHED_SOURCE_SHA256', digest(EXPECTED)).start()

    def test_exact_removal_preserves_every_other_file_and_original_source(self):
        before = files(self.source)
        record = damnlib_source.prepare_damnlib(self.source, self.output)
        self.assertEqual(files(self.source), before)
        expected = dict(before); expected[self.relative.as_posix()] = EXPECTED
        self.assertEqual(files(self.output), expected)
        self.assertEqual(record['prepared_files'], {p: digest(v) for p, v in expected.items()})
        self.assertEqual(record['source_files'], {p: digest(v) for p, v in before.items()})
        self.assertEqual(record['selected_layer'], '42.20')
        self.assertEqual(record['patch_id'], 'damnlib-native-battery-recipes-v1')
        self.assertNotIn(str(self.root), str(record))

    def test_known_fixed_copy_is_idempotent(self):
        self.target.write_bytes(EXPECTED)
        before = files(self.source)
        record = damnlib_source.prepare_damnlib(self.source, self.output)
        self.assertEqual(files(self.output), before)
        self.assertTrue(record['already_patched'])

    def test_unknown_or_future_active_source_fails_before_copy(self):
        self.target.write_bytes(ORIGINAL + b'upstream edit')
        with self.assertRaisesRegex(ValueError, 'Unknown damnlib'):
            damnlib_source.prepare_damnlib(self.source, self.output)
        self.assertFalse(self.output.exists())
        self.target.write_bytes(ORIGINAL)
        (self.source / '42.21').mkdir()
        (self.source / '42.21/mod.info').write_text('id=damnlib\n')
        with self.assertRaisesRegex(ValueError, 'active version is missing'):
            damnlib_source.prepare_damnlib(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_wrong_mod_or_links_reject_without_writing(self):
        info = self.source / '42.20/mod.info'; info.write_text('id=OtherMod\n')
        with self.assertRaisesRegex(ValueError, 'damnlib Mod ID'):
            damnlib_source.prepare_damnlib(self.source, self.output)
        info.write_text('id=damnlib\n')
        (self.source / 'linked').symlink_to(self.target)
        with self.assertRaisesRegex(ValueError, 'symbolic link'):
            damnlib_source.prepare_damnlib(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_changed_copy_or_source_cannot_be_published(self):
        copytree = shutil.copytree
        for mutate_source in (False, True):
            def changed(source, destination, *args, **kwargs):
                result = copytree(source, destination, *args, **kwargs)
                if Path(source) == self.source:
                    root = self.source if mutate_source else self.output
                    (root / 'common/unchanged.bin').write_bytes(b'concurrent edit')
                return result
            with self.subTest(source=mutate_source), patch.object(dependency_source.shutil, 'copytree', changed):
                with self.assertRaisesRegex(ValueError, 'changed during preparation'):
                    damnlib_source.prepare_damnlib(self.source, self.output)
            self.assertFalse(self.output.exists())

    def test_replacement_boundaries_and_result_are_guarded(self):
        for source in (ORIGINAL.replace(b'craftRecipe damnCraftInsert', b'craftRecipe Renamed'),
                       ORIGINAL.replace(b'    /************************ Rubber', b'    /* changed Rubber'),
                       ORIGINAL.replace(PAIR, PAIR + b'    craftRecipe Unexpected {}\r\n')):
            with self.subTest(source=source), self.assertRaises(ValueError):
                damnlib_source._patched(source)
        with patch.object(damnlib_source, 'PATCHED_SOURCE_SHA256', '0' * 64):
            with self.assertRaisesRegex(ValueError, 'differs from reviewed result'):
                damnlib_source.prepare_damnlib(self.source, self.output)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
