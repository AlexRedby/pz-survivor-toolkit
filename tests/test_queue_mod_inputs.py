"""Git state is not a mod artifact; every retained byte and snapshot guard stays exact."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import mod_inputs, native
from queue_checks.mod_selection import lua_sources


class ModInputTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'Artifact'
        self.source.mkdir()
        self.retained = ('42/mod.info', '42/media/lua/shared/runtime.lua', '42/media/scripts/item.txt',
                         '.gitignore', '.github/workflows/build.yml', '42/media/.hidden', '42/media/.gitconfig')
        for name in self.retained:
            self.write(name, 'id=Artifact\n' if name.endswith('mod.info') else name)
        self.write('.git/HEAD', 'main')
        self.write('.git/objects/blob', 'unused bytes')
        self.write('common/media/.git', 'gitdir: /unrelated/worktree')
        (self.source / '42/media/empty').mkdir()

    def write(self, name, value):
        path = self.source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def test_hash_copy_and_hidden_file_membership_share_one_exact_policy(self):
        strict = native.hashes(self.source)
        expected = {name: digest for name, digest in strict.items() if not mod_inputs.excluded(name)}
        self.assertEqual(set(self.retained), expected.keys())
        self.assertEqual(expected, mod_inputs.hashes(self.source))
        target = self.root / 'copy'
        mod_inputs.copy_tree(self.source, target)
        self.assertEqual(expected, native.hashes(target))
        self.assertTrue((target / '42/media/empty').is_dir())
        self.assertFalse(any(mod_inputs.excluded(path.relative_to(target)) for path in target.rglob('*')))
        for name in self.retained:
            self.assertEqual((self.source / name).read_bytes(), (target / name).read_bytes())

    def test_git_is_pruned_before_traversal_or_file_reads(self):
        scan, hash_file = mod_inputs.os.scandir, mod_inputs.progress.hash_file
        def guarded_scan(path):
            self.assertNotIn('.git', Path(path).relative_to(self.source).parts)
            return scan(path)
        def guarded_hash(path):
            self.assertFalse(mod_inputs.excluded(Path(path).relative_to(self.source)))
            return hash_file(path)
        with patch.object(mod_inputs.os, 'scandir', side_effect=guarded_scan), \
                patch.object(mod_inputs.progress, 'hash_file', side_effect=guarded_hash):
            self.assertEqual(set(self.retained), mod_inputs.hashes(self.source).keys())

    def test_git_add_remove_modify_do_not_change_artifacts_but_runtime_drift_does(self):
        expected = mod_inputs.hashes(self.source)
        (self.source / '.git/HEAD').write_text('another branch')
        (self.source / '.git/objects/blob').unlink()
        self.write('42/media/lua/shared/.git/new.lua', 'return false')
        self.assertEqual(expected, mod_inputs.hashes(self.source))
        self.assertNotEqual(expected, native.hashes(self.source))
        path = self.write('42/media/lua/shared/new.lua', 'return true')
        self.assertNotEqual(expected, mod_inputs.hashes(self.source))
        path.unlink()
        self.assertEqual(expected, mod_inputs.hashes(self.source))
        self.write('.gitignore', 'changed build input')
        self.assertNotEqual(expected, mod_inputs.hashes(self.source))

    def test_retained_root_file_directory_and_dangling_symlinks_fail_before_copy(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / 'data').write_text('outside')
        for destination in (outside, outside / 'data', outside / 'missing'):
            link = self.source / 'retained-link'
            link.symlink_to(destination, target_is_directory=destination == outside)
            try:
                with self.assertRaisesRegex(ValueError, 'symlinks are unsupported'):
                    mod_inputs.hashes(self.source)
                with self.assertRaisesRegex(ValueError, 'symlinks are unsupported'):
                    mod_inputs.copy_tree(self.source, self.root / 'bad-copy')
                self.assertFalse((self.root / 'bad-copy').exists())
            finally:
                link.unlink()
        link = self.root / 'root-link'
        link.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlinks are unsupported'):
            mod_inputs.hashes(link)

    def test_excluded_git_link_and_fifo_are_never_followed(self):
        pointer = self.source / 'common/media/.git'
        pointer.unlink()
        pointer.symlink_to(self.root / 'missing-external-metadata', target_is_directory=True)
        self.assertEqual(set(self.retained), mod_inputs.hashes(self.source).keys())
        mod_inputs.copy_tree(self.source, self.root / 'copy')
        self.assertFalse((self.root / 'copy/common/media/.git').exists())
        if hasattr(os, 'mkfifo'):
            os.mkfifo(self.source / '.git/pipe')
            self.assertEqual(set(self.retained), mod_inputs.hashes(self.source).keys())
            os.mkfifo(self.source / 'retained-pipe')
            with self.assertRaisesRegex(ValueError, 'regular files'):
                mod_inputs.hashes(self.source)

    def test_discovery_and_effective_lua_cannot_pick_up_git_copies(self):
        self.write('.git/fake/42/mod.info', 'id=Artifact\n')
        self.write('42/media/lua/shared/.git/fake.lua', 'not runtime')
        infos = mod_inputs.infos(self.root)
        self.assertEqual([self.source / '42/mod.info'], infos)
        (self.root / 'unrelated-link').symlink_to(self.root / 'missing', target_is_directory=True)
        self.assertEqual(infos, mod_inputs.infos(self.root))
        self.assertEqual([self.source / '42/media/lua/shared/runtime.lua'], lua_sources(self.source))
        self.assertEqual({'Artifact': self.source.resolve()}, native._locations(self.root, [], ['Artifact']))

    def test_seed_maps_require_the_current_policy_and_exact_relative_digests(self):
        row = dict(id='Artifact', input_policy=mod_inputs.POLICY, files=mod_inputs.hashes(self.source))
        self.assertEqual({'Artifact': row['files']}, mod_inputs.manifest_files([row]))
        for change in ({'input_policy': None}, {'input_policy': 'legacy'}, {'id': '../escape'},
                       {'files': {'.git/HEAD': 'a' * 64}}, {'files': {'../outside': 'a' * 64}},
                       {'files': {'runtime.lua': 'not a digest'}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                mod_inputs.manifest_files([dict(row, **change)])
        with self.assertRaises(ValueError):
            mod_inputs.manifest_files([row, row])


if __name__ == '__main__':
    unittest.main()
