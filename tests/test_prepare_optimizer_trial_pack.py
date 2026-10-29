"""Pin package inputs and candidate provenance independently of dirty checkout files."""
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.prepare_optimizer_trial import (BRIDGE, LAUNCHERS, build_bridge, bridge_resources,
                                           diagnostic_selection, prepare, record_java_source, snapshot_java_source, snapshot_pack)
from tools.queue_checks.mod_selection import metadata


class MainPackSnapshot(unittest.TestCase):
    def test_dirty_checkout_cannot_replace_pinned_main_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp).resolve()
            repo = base / 'repo'
            repo.mkdir()
            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.email', 'fixture@example.invalid')
            git('config', 'user.name', 'Fixture')
            (repo / 'PZSurvivorToolkit').mkdir()
            (repo / 'JavaPatches').mkdir()
            (repo / 'PZSurvivorToolkit/mod.info').write_text('id=LatestToolkit\n')
            (repo / 'JavaPatches/build.py').write_text('# pinned builder\n')
            (repo / 'SurvivorQoL-selected.ini').write_text('Mods=LatestToolkit\n')
            git('add', '.')
            git('commit', '-qm', 'Fixture main')
            pinned = git('rev-parse', 'HEAD')
            (repo / 'PZSurvivorToolkit/mod.info').write_text('id=WrongCheckout\n')
            (repo / 'SurvivorQoL-selected.ini').write_text('Mods=WrongCheckout\n')
            destination = base / 'snapshot'
            self.assertEqual(pinned, snapshot_pack(repo, destination, pinned))
            self.assertEqual('id=LatestToolkit\n', (destination / 'PZSurvivorToolkit/mod.info').read_text())
            self.assertEqual('Mods=LatestToolkit\n', (destination / 'SurvivorQoL-selected.ini').read_text())
            self.assertEqual('id=WrongCheckout\n', (repo / 'PZSurvivorToolkit/mod.info').read_text())
            self.assertFalse((destination / '.git').exists())

    def test_unknown_ref_does_not_create_snapshot(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / 'snapshot'
            with self.assertRaises(subprocess.CalledProcessError):
                snapshot_pack(ROOT, dest, 'nonexistent-trial-pack-reference')
            self.assertFalse(dest.exists())


class LocalCandidatePackage(unittest.TestCase):
    def test_package_records_local_candidate_and_distinct_profile_source(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp).resolve()
            repo = base / 'repo'
            repo.mkdir()
            def write(name, text):
                path = repo / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.email', 'fixture@example.invalid')
            git('config', 'user.name', 'Fixture')
            write('PZSurvivorToolkit/42/mod.info', 'id=PZSurvivorToolkit\nmodversion=0.1.284\n')
            dashboard = 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDashboardTextures.lua'
            write(dashboard, '-- committed dashboard\n')
            selected = ('# Main gameplay selection stays intact.\n'
                        'Mods=PZSurvivorToolkit;NMBJABBA;NewMusic;NMBJQ;PZToolkitJavaPatches;NMBJFM\n'
                        'WorkshopItems=123;3784065691;789;3777937059;456;3751236222\n'
                        'NightLength=2\n')
            write('SurvivorQoL-selected.ini', selected)
            write('JavaPatches/build.py', "from pathlib import Path\np=Path(__file__).parent/'build/PZToolkitJavaPatches/42/mod.info'\np.parent.mkdir(parents=True)\np.write_text('id=PZToolkitJavaPatches\\nmodversion=0.1.65\\n')\n")
            git('add', '.')
            git('commit', '-qm', 'Fixture base')
            main = git('rev-parse', 'HEAD')
            git('update-ref', 'refs/remotes/origin/main', main)
            write('PZSurvivorToolkit/42/mod.info', 'id=PZSurvivorToolkit\nmodversion=0.1.285\n')
            git('commit', '-qam', 'Fixture local candidate')
            candidate = git('rev-parse', 'HEAD')
            # An uncommitted product edit cannot silently become the identified candidate.
            write('PZSurvivorToolkit/42/mod.info', 'id=PZSurvivorToolkit\nmodversion=0.1.999\n')
            write(dashboard, '-- dirty dashboard must not enter the bridge or pack\n')
            for name in LAUNCHERS:
                write('tests/optimizer_trial/' + name, 'fixture')
            profile_revision = 'c' * 40
            write('tests/optimizer_trial/candidate-manifest.json', json.dumps({
                'format': 2, 'toolkit_source_revision': profile_revision, 'profile': {'id': 'measured-profile'}}))
            for name in ('PZOptimizerTrialPack.lua', 'PZOptimizerTrialTelemetry.lua'):
                write('tests/optimizer_trial/' + name, '-- fixture')
            for name in ('Launch.ps1', 'Record-JFR.ps1', 'Record-JFR.cmd', 'mods/PZDrivingBench/42/mod.info'):
                write('tests/driving_benchmark/' + name, 'fixture')
            def fixture_bridge(destination, *args):
                mod = destination / BRIDGE
                for name in (f'42/media/java/{BRIDGE}.jar',):
                    path = mod / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(b'fixture bridge')
                return mod
            with mock.patch('tools.prepare_optimizer_trial.build_bridge', side_effect=fixture_bridge):
                output, archive = prepare(base / 'package', base / 'game', base / 'jdk', root=repo)
            pack = json.loads((output / 'pack-manifest.json').read_text())
            receipt = json.loads((output / 'build-receipt.json').read_text())
            effective_mods = ['PZSurvivorToolkit', 'NewMusic', 'PZToolkitJavaPatches']
            effective_workshop = ['123', '789', '456']
            self.assertEqual(effective_mods, pack['mod_ids'])
            self.assertEqual(effective_workshop, pack['workshop_ids'])
            exclusions = pack['excluded_mods']
            self.assertEqual({('NMBJABBA', '3784065691'), ('NMBJQ', '3777937059'),
                              ('NMBJFM', '3751236222')},
                             {(entry['mod_id'], entry['workshop_id']) for entry in exclusions})
            self.assertEqual(3, len(exclusions))
            self.assertTrue(all(isinstance(entry['reason'], str) and entry['reason'].strip()
                                for entry in exclusions))
            self.assertEqual(exclusions, receipt['excluded_mods'])
            self.assertEqual(len(effective_mods), receipt['selected_mod_count'])
            packaged_selection = metadata(output / 'SurvivorQoL-selected.ini')
            self.assertEqual({'Mods': ';'.join(effective_mods),
                              'WorkshopItems': ';'.join(effective_workshop), 'NightLength': '2'},
                             packaged_selection)
            host = metadata(output / 'Server/PZOptimizerHost.ini')
            self.assertEqual(';'.join(effective_mods + [BRIDGE]), host['Mods'])
            self.assertEqual(packaged_selection['WorkshopItems'], host['WorkshopItems'])
            self.assertEqual('2', host['NightLength'])
            self.assertEqual(selected, (repo / 'SurvivorQoL-selected.ini').read_text())
            self.assertEqual(selected, git('show', candidate + ':SurvivorQoL-selected.ini') + '\n')
            for proof in (pack, receipt):
                self.assertEqual('local-candidate', proof['source_kind'])
                self.assertEqual(candidate, proof['source_revision'])
                self.assertEqual(candidate, proof['main_revision'])
                self.assertEqual(main, proof['base_revision'])
                self.assertEqual(main, proof['base_ref_revision'])
            self.assertNotEqual(main, candidate)
            self.assertEqual('0.1.285', pack['repository_mods']['PZSurvivorToolkit']['version'])
            shipped_dashboard = output / 'mods' / dashboard
            self.assertEqual('-- committed dashboard\n', shipped_dashboard.read_text())
            self.assertEqual([shipped_dashboard], list((output / 'mods').rglob('*Dashboard*.lua')))
            self.assertEqual(hashlib.sha256(shipped_dashboard.read_bytes()).hexdigest(), receipt['dashboard_sha256'])
            self.assertEqual(profile_revision, receipt['optimizer_candidate']['profile_source_revision'])
            self.assertNotEqual(profile_revision, receipt['source_revision'])
            self.assertEqual('3.6', receipt['diagnostics_revision'])
            for name in ('TrialProcess.cs','TrialProcess.ps1','TrialStorage.ps1','TrialWprTools.ps1','TrialWprWorker.ps1','Test-WPR.ps1','Test-WPR.cmd'):
                self.assertEqual(hashlib.sha256((output / name).read_bytes()).hexdigest(), receipt['diagnostics_files_sha256'][name])
            self.assertEqual(hashlib.sha256((output / 'PZTrial.wprp').read_bytes()).hexdigest(),
                             receipt['wpr_profile']['sha256'])
            expected = output / 'mods' / BRIDGE / '42/media/lua/client/PZOptimizerTrialExpectedMods.lua'
            self.assertIn('revision=' + json.dumps(candidate), expected.read_text())
            lua_ids = re.search(r'ids=\{([^}]*)\}', expected.read_text())
            self.assertIsNotNone(lua_ids)
            self.assertEqual(effective_mods + ['PZDrivingBench', BRIDGE],
                             json.loads('[' + lua_ids.group(1) + ']'))
            with zipfile.ZipFile(archive) as bundle:
                self.assertEqual(receipt, json.loads(bundle.read('PZDrivingOptimizerTrial/build-receipt.json')))
                self.assertEqual((output / 'PZTrial.wprp').read_bytes(),
                                 bundle.read('PZDrivingOptimizerTrial/PZTrial.wprp'))


class DiagnosticSelection(unittest.TestCase):
    def test_pack_without_unavailable_music_is_unchanged_and_copied(self):
        settings = {'Mods': 'PZSurvivorToolkit;NewMusic;PZToolkitJavaPatches',
                    'WorkshopItems': '123;789;456', 'NightLength': '2'}
        effective, exclusions = diagnostic_selection(settings)
        self.assertIsNot(settings, effective)
        self.assertEqual(settings, effective)
        self.assertEqual([], exclusions)

    def test_partial_music_pair_is_rejected_without_mutating_settings(self):
        for mod, workshop in [('NMBJABBA', '3784065691'), ('NMBJQ', '3777937059'),
                              ('NMBJFM', '3751236222')]:
            for present in ('mod', 'workshop'):
                with self.subTest(mod=mod, present=present):
                    settings = {'Mods': 'PZSurvivorToolkit;NewMusic' + (';' + mod if present == 'mod' else ''),
                                'WorkshopItems': '123;789' + (';' + workshop if present == 'workshop' else '')}
                    original = dict(settings)
                    with self.assertRaises(ValueError):
                        diagnostic_selection(settings)
                    self.assertEqual(original, settings)


class ExplicitJavaSource(unittest.TestCase):
    def repo(self, base):
        repo = base / 'repo'
        java = repo / 'JavaPatches'
        (java / 'src/example').mkdir(parents=True)
        (java / 'tools').mkdir()
        (java / 'build.py').write_text('# reviewed builder\n')
        (java / 'tools/RelocateKotlin.java').write_text('class RelocateKotlin {}\n')
        (java / 'src/example/Patch.kt').write_text('class Original\n')
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Fixture',
                        '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Fixture source'], check=True)
        revision = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
        return java, revision

    def test_explicit_dirty_source_records_base_and_only_build_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp).resolve()
            java, revision = self.repo(base)
            (java / 'src/example/Patch.kt').write_text('class ReviewedCandidate\n')
            (java / 'build/cache').mkdir(parents=True)
            (java / 'build/cache/stale.class').write_bytes(b'old compiled output')
            (java / 'src/example/__pycache__').mkdir()
            (java / 'src/example/__pycache__/cache.pyc').write_bytes(b'cache')
            (java / 'tests').mkdir()
            (java / 'tests/check.kt').write_text('class TestOnly\n')
            destination = base / 'snapshot/JavaPatches'
            destination.mkdir(parents=True)
            (destination / 'stale-source.java').write_text('class Stale {}')
            identity = snapshot_java_source(java, destination)
            self.assertEqual(revision, identity['base_revision'])
            self.assertEqual('explicit-working-source', identity['mode'])
            self.assertEqual({'build.py', 'tools/RelocateKotlin.java', 'src/example/Patch.kt'}, set(identity['files']))
            self.assertEqual('class ReviewedCandidate\n', (destination / 'src/example/Patch.kt').read_text())
            self.assertEqual(identity['files']['src/example/Patch.kt'], hashlib.sha256(b'class ReviewedCandidate\n').hexdigest())
            self.assertFalse((destination / 'build').exists())
            self.assertFalse((destination / 'tests').exists())
            self.assertFalse((destination / 'src/example/__pycache__').exists())
            self.assertFalse((destination / 'stale-source.java').exists())
            self.assertNotIn(str(base), json.dumps(identity))
            first = identity['fingerprint_sha256']
            (java / 'src/example/Patch.kt').write_text('class DifferentCandidate\n')
            self.assertNotEqual(first, snapshot_java_source(java, base / 'second')['fingerprint_sha256'])

    def test_linked_or_binary_runtime_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp).resolve()
            java, _ = self.repo(base)
            (java / 'src/example/linked.kt').symlink_to(java / 'src/example/Patch.kt')
            with self.assertRaisesRegex(ValueError, 'Linked Java runtime'):
                snapshot_java_source(java, base / 'linked')
            (java / 'src/example/linked.kt').unlink()
            (java / 'src/example/stale.class').write_bytes(b'stale')
            with self.assertRaisesRegex(ValueError, 'generated or binary'):
                snapshot_java_source(java, base / 'binary')
            self.assertFalse((base / 'linked').exists())
            self.assertFalse((base / 'binary').exists())

    def test_jar_proof_keeps_builder_fingerprints_and_adds_explicit_source(self):
        with tempfile.TemporaryDirectory() as temp:
            jar = Path(temp) / 'candidate.jar'
            resource = 'META-INF/pztoolkit-build-inputs.json'
            original = {'format': 1, 'sources': {'src/Patch.kt': 'a' * 64}}
            identity = {'mode': 'explicit-working-source', 'base_revision': '1' * 40,
                        'fingerprint_sha256': '2' * 64, 'files': {'src/Patch.kt': 'a' * 64}}
            with zipfile.ZipFile(jar, 'w') as archive:
                archive.writestr(resource, json.dumps(original))
                archive.writestr('example/Patch.class', b'compiled-candidate')
            record_java_source(jar, identity)
            with zipfile.ZipFile(jar) as archive:
                manifest = json.loads(archive.read(resource))
                self.assertEqual(original['sources'], manifest['sources'])
                self.assertEqual(identity, manifest['optimizer_trial_source'])
                self.assertEqual(b'compiled-candidate', archive.read('example/Patch.class'))
                self.assertEqual(2, len(archive.namelist()))


class BridgeManifestResources(unittest.TestCase):
    def candidate(self):
        return {'format': 2, 'selected_files': {'pzopt/Helper.class': 'a' * 64},
                'profile': {'id': 'reviewed-bounded-profile', 'properties': {'enabled': 'true', 'devHordeModes': ''}},
                'lifecycle_guards': {'zombie/GameWindow.class': 'b' * 64}}

    def test_bridge_embeds_exact_candidate_maps_at_jar_root(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp).resolve()
            root = base / 'root'
            source = root / 'tests/optimizer_trial/java'
            source.mkdir(parents=True)
            (source / 'Main.java').write_text('class Main {}')
            (source / 'mod.info.template').write_text(f'id={BRIDGE}\njavaJarFile=media/java/{BRIDGE}.jar\n')
            candidate = source.parent / 'candidate-manifest.json'
            candidate.write_text(json.dumps(self.candidate()))
            game = base / 'game'
            game.mkdir()
            for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
                (game / name).write_bytes(b'fixture')
            def compile_fixture(command, **kwargs):
                classes = Path(command[command.index('-d') + 1])
                (classes / 'Main.class').write_bytes(b'compiled')
            with mock.patch('tools.prepare_optimizer_trial.subprocess.run', side_effect=compile_fixture):
                mod = build_bridge(base / 'mods', game, base / 'jdk', root)
            self.assertFalse(list(mod.rglob('*.lua')), 'bridge must not duplicate Toolkit Lua modules')
            with zipfile.ZipFile(mod / f'42/media/java/{BRIDGE}.jar') as jar:
                self.assertEqual(b'pzopt/Helper.class=' + b'a' * 64 + b'\n', jar.read('optimizer-trial-selected.properties'))
                self.assertEqual(b'devHordeModes=\nenabled=true\n', jar.read('optimizer-trial-profile.properties'))
                self.assertEqual(b'zombie/GameWindow.class=' + b'b' * 64 + b'\n', jar.read('optimizer-trial-native.properties'))
                self.assertEqual(b'compiled', jar.read('Main.class'))

    def test_extended_manifest_requires_profile_and_valid_resource_hashes(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp).resolve() / 'candidate.json'
            candidate = self.candidate()
            del candidate['profile']['properties']
            path.write_text(json.dumps(candidate))
            with self.assertRaisesRegex(ValueError, 'explicit profile'):
                bridge_resources(path)
            candidate = self.candidate()
            candidate['selected_files']['../escaped.class'] = 'c' * 64
            path.write_text(json.dumps(candidate))
            with self.assertRaisesRegex(ValueError, 'resource/hash'):
                bridge_resources(path)


if __name__ == '__main__':
    unittest.main()
