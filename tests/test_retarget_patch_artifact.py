"""Retargeting executes a complete current mixed build, never stale Java source overlays."""
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from JavaPatches import build
import retarget_metal_cart_pickup as retarget
import generate_shopping_cart_pickup as shopping
import generate_cart_locomotion as locomotion


class RetargetPatchArtifact(unittest.TestCase):
    def setUp(self):
        self.cache = tempfile.TemporaryDirectory()
        self.addCleanup(self.cache.cleanup)
        self.root = Path(self.cache.name)
        self.source = self.root / 'JavaPatches'
        self.runtime = self.source / 'src/net/alexredby/pztoolkitjavapatches'
        self.runtime.mkdir(parents=True)
        (self.source / 'build.py').write_text('build input')
        (self.source / 'tools').mkdir()
        (self.source / 'tools/RelocateKotlin.java').write_text('shader input')
        (self.runtime / 'CartWheelbarrow.kt').write_text('Kotlin runtime input')
        (self.runtime / 'CartWorldSupport.java').write_text('remaining Java runtime input')
        self.jar = self.root / 'current.jar'
        self.archive()

    def archive(self):
        classes = self.root / 'classes'
        build.write_source_manifest(self.source, classes)
        with ZipFile(self.jar, 'w') as archive:
            archive.write(classes / build.SOURCE_MANIFEST, build.SOURCE_MANIFEST)

    def test_current_manifest_is_portable_and_excludes_independent_bootstrap(self):
        build.require_current_patch_jar(self.jar, self.source)
        bootstrap = self.source / 'src/net/alexredby/pztoolkitbootstrap/FontAssets.java'
        bootstrap.parent.mkdir(parents=True)
        bootstrap.write_text('independent early font input')
        build.require_current_patch_jar(self.jar, self.source)
        with ZipFile(self.jar) as archive:
            manifest = json.loads(archive.read(build.SOURCE_MANIFEST))
        self.assertNotIn(str(self.root), json.dumps(manifest))
        self.assertEqual(set(manifest['sources']), {'build.py', 'tools/RelocateKotlin.java',
            'src/net/alexredby/pztoolkitjavapatches/CartWheelbarrow.kt',
            'src/net/alexredby/pztoolkitjavapatches/CartWorldSupport.java'})

    def test_changed_added_deleted_and_renamed_runtime_or_build_inputs_are_rejected(self):
        for relative in ('build.py', 'tools/RelocateKotlin.java',
                         'src/net/alexredby/pztoolkitjavapatches/CartWheelbarrow.kt',
                         'src/net/alexredby/pztoolkitjavapatches/CartWorldSupport.java'):
            path = self.source / relative
            before = path.read_bytes()
            with self.subTest(relative=relative):
                path.write_bytes(before + b' changed')
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    build.require_current_patch_jar(self.jar, self.source)
                path.write_bytes(before)
        original = self.runtime / 'CartWorldSupport.java'
        moved = original.with_suffix('.kt')
        original.rename(moved)
        with self.assertRaisesRegex(ValueError, 'does not match'):
            build.require_current_patch_jar(self.jar, self.source)
        moved.rename(original)
        added = self.runtime / 'NewHelper.kt'
        added.write_text('new runtime input')
        with self.assertRaisesRegex(ValueError, 'does not match'):
            build.require_current_patch_jar(self.jar, self.source)
        added.unlink()
        original.unlink()
        with self.assertRaisesRegex(ValueError, 'does not match'):
            build.require_current_patch_jar(self.jar, self.source)

    def test_legacy_or_invalid_artifact_fails_before_any_compiler_or_output(self):
        for data in (None, b'invalid JSON', b'[]'):
            with self.subTest(data=data):
                with ZipFile(self.jar, 'w') as archive:
                    if data is not None:
                        archive.writestr(build.SOURCE_MANIFEST, data)
                with patch.object(retarget, 'ROOT', self.root), patch.object(retarget.subprocess, 'run') as run:
                    with self.assertRaises(ValueError):
                        retarget.solve([], {}, self.root / 'game', self.root / 'jdk', self.jar)
                    with self.assertRaises(ValueError):
                        retarget.verify_native('candidate', self.root / 'game', self.root / 'jdk', self.jar)
                    run.assert_not_called()

    def test_generators_reject_missing_or_stale_kotlin_artifact_before_native_inputs_or_compilation(self):
        candidate = self.source / 'build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'
        candidate.parent.mkdir(parents=True)
        for artifact in ('missing', 'legacy', 'stale Kotlin'):
            if artifact == 'legacy':
                with ZipFile(candidate, 'w'):
                    pass
            elif artifact == 'stale Kotlin':
                candidate.write_bytes(self.jar.read_bytes())
                (self.runtime / 'CartWheelbarrow.kt').write_text('changed Kotlin runtime')
            for module in (shopping, locomotion):
                with self.subTest(artifact=artifact, tool=module.__name__), \
                        patch.object(module, 'ROOT', self.root), \
                        patch.object(sys, 'argv', ['tool', '--game', str(self.root / 'absent game'),
                                                   '--jdk', str(self.root / 'jdk'),
                                                   '--cart-idle', str(self.root / 'absent cart')]), \
                        patch.object(module.subprocess, 'run') as run, \
                        patch.object(module.tempfile, 'TemporaryDirectory') as temporary:
                    with self.assertRaisesRegex(ValueError, 'Rebuild JavaPatches/build.py'):
                        module.main()
                    run.assert_not_called()
                    temporary.assert_not_called()
        self.assertFalse((self.root / 'assets').exists())
        self.assertFalse((self.root / 'PZSurvivorToolkit').exists())

    def test_generators_accept_current_mixed_artifact_for_helper_compilation(self):
        candidate = self.source / 'build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'
        candidate.parent.mkdir(parents=True)
        candidate.write_bytes(self.jar.read_bytes())
        game = self.root / 'game'
        for name in ('MaleBody.x', 'FemaleBody.x', 'Clothes/Bob_Trousers.x', 'Clothes/Kate_Trousers.x'):
            model = game / 'media/models_X/Skinned' / name
            model.parent.mkdir(parents=True, exist_ok=True)
            model.write_text('unweighted root')
        for module in (shopping, locomotion):
            with self.subTest(tool=module.__name__), patch.object(module, 'ROOT', self.root), \
                    patch.object(sys, 'argv', ['tool', '--game', str(game), '--jdk', str(self.root / 'jdk'),
                                               '--cart-idle', str(self.root / 'cart')]), \
                    patch.object(module.subprocess, 'run', side_effect=RuntimeError('compiler reached')) as run:
                with self.assertRaisesRegex(RuntimeError, 'compiler reached'):
                    module.main()
                command = run.call_args.args[0]
                self.assertEqual(Path(command[0]).name, 'javac')
                self.assertIn(str(candidate), command[command.index('-cp') + 1].split(os.pathsep))
                self.assertFalse(any('/JavaPatches/src/' in str(arg) for arg in command))

    def test_native_solve_and_replay_compile_only_their_tool_against_verified_jar(self):
        commands = []
        def run(command, **kwargs):
            commands.append(command)
            if 'net.alexredby.pztoolkitjavapatches.CartMetalPickupRetarget' in command:
                output = Path(command[-2])
                output.write_bytes(struct.pack('>i16f', 1, *range(16)))
        samples = [{'time': .5, 'bones': {'Bip01_L_Thigh': list(range(16))}}]
        with patch.object(retarget, 'ROOT', self.root), patch.object(retarget.subprocess, 'run', side_effect=run):
            retarget.solve(samples, {'Bip01_L_Thigh': None}, self.root / 'game', self.root / 'jdk', self.jar)
            retarget.verify_native('candidate', self.root / 'game', self.root / 'jdk', self.jar)
        compilers = [command for command in commands if Path(command[0]).name == 'javac']
        self.assertEqual(len(compilers), 2)
        self.assertEqual([[Path(arg).name for arg in command if str(arg).endswith('.java')] for command in compilers],
                         [['CartMetalPickupRetarget.java'], ['CartMetalPickupReplay.java']])
        self.assertTrue(all(str(self.jar) in command[command.index('-cp') + 1] for command in commands))


if __name__ == '__main__':
    unittest.main()
