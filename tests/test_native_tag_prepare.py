"""The tag CLI prepares current and historical product inputs through the shared runner."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import admission, native, runner

spec = importlib.util.spec_from_file_location('native_tag_prepare', ROOT / 'tests/native_tags/run.py')
tags = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tags)


class NativeTagPreparation(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.project, self.workshop, self.game, self.jdk = [self.root / name for name in
                                                         ('project', 'workshop', 'game', 'jdk')]
        self.fixture = self.project / 'tests/native_tags'
        self.identifiers = ['Unrelated', 'organizedCategories_core', 'CleanUI', 'PZToolkitJavaPatches',
                            'PZSurvivorToolkit', 'BravoItemDetails', 'EURY_CONTAINERS', 'NeatUI_Framework']
        self.write(self.project / 'SurvivorQoL-selected.ini', 'Mods = ' + ';'.join(self.identifiers) + '\n')
        self.mod(self.project / 'PZSurvivorToolkit', 'PZSurvivorToolkit')
        self.visuals = self.project / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TagVisuals.lua'
        self.write(self.visuals, 'return {"Item_Current"}\n')
        for identifier in self.identifiers:
            if identifier not in ('PZSurvivorToolkit', 'PZToolkitJavaPatches'):
                self.mod(self.workshop / identifier, identifier, 'common' if identifier == 'CleanUI' else '42.20')
        self.java = self.mod(self.project / 'JavaPatches/build/PZToolkitJavaPatches', 'PZToolkitJavaPatches')
        self.write(self.java / '42/media/java/PZToolkitJavaPatches.jar', 'current local Java build')
        for relative in ('projectzomboid.jar', 'media/lua/shared/native.lua', 'media/scripts/items.txt'):
            self.write(self.game / relative, 'native input')
        for name in ('java', 'javac'):
            executable = native.jdk_binary(self.jdk, name)
            self.write(executable, 'fake Java executable')
            executable.chmod(0o755)
        shutil.copytree(ROOT / 'tests/native_queue/support', self.project / 'tests/native_queue/support')
        self.write(self.project / 'tests/native_queue/catalog.json', '{}\n')
        self.write(self.project / 'tools/check_action_queue.py', '# current CLI\n')
        self.write(self.project / 'tools/queue_checks/native.py', '# current preparation implementation\n')
        for side in ('client', 'shared', 'server'):
            self.write(self.fixture / side / 'tag.lua', '-- current ' + side + ' fixture\n')
        self.real_run = subprocess.run
        self.start_patch(patch.object(admission.shutil, 'disk_usage',
                                      return_value=SimpleNamespace(free=100 * 1024**3)))
        self.start_patch(patch.object(admission, 'STATE', self.root / 'admission-state'))
        self.start_patch(patch.object(admission.host, 'sample', return_value={'processes': []}))
        self.start_patch(patch.object(tags, 'ROOT', self.project))
        self.start_patch(patch.object(tags, 'HERE', self.fixture))
        self.start_patch(patch.object(native.subprocess, 'run', side_effect=self.compile_or_run))
        self.launch = self.start_patch(patch.object(runner, 'run', side_effect=AssertionError('Unexpected game launch')))

    def start_patch(self, value):
        result = value.start()
        self.addCleanup(value.stop)
        return result

    @staticmethod
    def write(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding='utf-8')

    def mod(self, path, identifier, layer='42'):
        self.write(path / layer / 'mod.info', 'id=' + identifier + '\nversion=1\n')
        self.write(path / layer / 'media/lua/shared/product.lua', 'return ' + repr(identifier) + '\n')
        return path

    def compile_or_run(self, command, **kwargs):
        if Path(command[0]).name in ('javac', 'javac.exe'):
            for value in command:
                if str(value).endswith('.java'):
                    Path(value).with_suffix('.class').write_bytes(b'fake class')
            return subprocess.CompletedProcess(command, 0)
        return self.real_run(command, **kwargs)

    def invoke(self, *arguments):
        output = self.root / 'prepared'
        argv = ['run.py', str(output), '--game', str(self.game), '--jdk', str(self.jdk),
                '--workshop', str(self.workshop), '--prepare-only', *arguments]
        with patch.object(sys, 'argv', argv), redirect_stdout(io.StringIO()):
            tags.main()
        self.launch.assert_not_called()
        return output

    @staticmethod
    def read_json(path):
        return json.loads(path.read_text())

    def test_default_uses_current_ini_order_without_requiring_standalone_quartermaster(self):
        workshop_before = native.hashes(self.workshop)
        toolkit_before = native.hashes(self.project / 'PZSurvivorToolkit')
        output = self.invoke()
        expected = [identifier for identifier in self.identifiers
                    if identifier not in ('Unrelated', 'PZToolkitJavaPatches')]
        selected = self.read_json(output / 'run/selection.json')
        self.assertEqual(expected, selected['mods'])
        self.assertEqual(['Item_Current'], selected['textureNames'])
        self.assertEqual(tags.CASES, selected['cases'])
        manifest = self.read_json(output / 'run/manifest.json')
        clean = next(row for row in manifest if row['id'] == 'CleanUI')
        self.assertEqual(str(self.workshop / 'CleanUI'), clean['source'])
        self.assertEqual(workshop_before, native.hashes(self.workshop))
        self.assertEqual(toolkit_before, native.hashes(self.project / 'PZSurvivorToolkit'))
        self.assertFalse((output / 'source/CleanUI').exists())
        self.assertFalse((output / 'source/PZSurvivorToolkit/common').exists())
        for role in tags.ROLES:
            self.assertTrue((output / 'run' / role / 'mods/CleanUI/42.0/media/AnimSets').is_dir())
            self.assertTrue((output / 'run' / role / 'mods/CleanUI/common/media/actiongroups').is_dir())
        self.assertTrue((output / 'run/snapshot-hashes.json').is_file())

    def test_full_selected_pack_uses_local_java_override_and_shared_workshop_sources(self):
        # A Workshop copy must not replace the explicitly built local Java component.
        self.mod(self.workshop / 'obsolete-java', 'PZToolkitJavaPatches')
        output = self.invoke('--selected')
        selected = self.read_json(output / 'run/selection.json')
        self.assertEqual(self.identifiers, selected['mods'])
        self.assertEqual(str(self.java), selected['options']['mod_sources']['PZToolkitJavaPatches'])
        manifest = self.read_json(output / 'run/manifest.json')
        java = next(row for row in manifest if row['id'] == 'PZToolkitJavaPatches')
        self.assertEqual(str(self.java), java['source'])
        for role in tags.ROLES:
            jar = output / 'run' / role / 'mods/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'
            self.assertEqual('current local Java build', jar.read_text())
        self.assertFalse((output / 'source/PZToolkitJavaPatches').exists())

    def test_historical_product_keeps_its_selection_but_uses_current_tools_and_fixture(self):
        historical = ['CleanUI', 'PZSurvivorToolkit', 'Quartermaster', 'organizedCategories_core',
                      'BravoItemDetails', 'EURY_CONTAINERS', 'NeatUI_Framework']
        ini = self.project / 'SurvivorQoL-selected.ini'
        self.write(ini, 'Mods=' + ';'.join(historical) + '\n')
        self.write(self.visuals, 'return {"Item_Historical"}\n')
        self.mod(self.project / 'PZSurvivorWishlist', 'PZSurvivorWishlist')
        old_tool = self.project / 'tools/check_action_queue.py'
        self.write(old_tool, 'raise RuntimeError("archived tool must not execute")\n')
        old_preflight = self.project / 'tests/native_queue/support/ZZReleasePreflight.lua'
        current_preflight = old_preflight.read_text()
        self.write(old_preflight, '-- archived preflight\n')
        for command in (['git', 'init', '-q'], ['git', 'add', '.'],
                        ['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                         'commit', '-qm', 'Historical product']):
            self.real_run(command, cwd=self.project, check=True, capture_output=True)
        self.write(ini, 'Mods=PZSurvivorToolkit\n')
        self.write(self.visuals, 'return {"Item_Current"}\n')
        self.write(old_tool, '# current CLI\n')
        self.write(old_preflight, current_preflight)
        self.mod(self.workshop / 'Quartermaster', 'Quartermaster')
        output = self.invoke('--source-ref', 'HEAD', '--baseline')
        selected = self.read_json(output / 'run/selection.json')
        self.assertEqual(historical, selected['mods'])
        self.assertEqual(['Item_Historical'], selected['textureNames'])
        self.assertEqual(tags.BASELINE, selected['cases'])
        self.assertTrue((output / 'source/PZSurvivorWishlist/42/mod.info').is_file())
        self.assertEqual('# current CLI\n', (output / 'source/tools/check_action_queue.py').read_text())
        staged_preflight = output / 'source/tests/native_queue/support/ZZReleasePreflight.lua'
        self.assertEqual(current_preflight, staged_preflight.read_text())
        for role in tags.ROLES:
            fixture = output / 'run' / role / 'mods/ActionQueueTest/42/media/lua/client/tag.lua'
            self.assertEqual('-- current client fixture\n', fixture.read_text())

    def test_ambiguous_workshop_mod_is_rejected_by_the_shared_resolver(self):
        other = self.root / 'other-workshop'
        self.mod(other / 'another-cleanui', 'CleanUI')
        with self.assertRaisesRegex(ValueError, 'Mod ID must resolve exactly once: CleanUI'):
            self.invoke('--workshop', str(other))
        self.launch.assert_not_called()
        self.assertFalse((self.root / 'prepared/run').exists())
