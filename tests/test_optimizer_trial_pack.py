"""Current-main pack preflight/profile tests. Uses pwsh, never launches the game."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
LAUNCHER = ROOT / 'tests/optimizer_trial/Launch-Trial.ps1'


def ps(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(PWSH, 'PowerShell required')
class TrialPackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pz pack ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.package, self.source, self.workshop, self.cache = [self.root / name for name in ('package', 'source', 'workshop', 'cache')]
        self.cache.mkdir()
        self.source.mkdir()
        self.package.mkdir()
        (self.package / 'Server').mkdir()
        self.ids = ['ZombieBuddy', 'ThirdParty', 'PZSurvivorToolkit', 'PZToolkitJavaPatches']
        for name in ('PZSurvivorToolkit', 'PZToolkitJavaPatches', 'PZDrivingBench', 'PZDrivingOptimizerBridge'):
            self.mod(self.package / 'mods' / name, name)
        self.mod(self.workshop / '123/mods/ZB', 'ZombieBuddy')
        self.mod(self.workshop / '456/mods/Third', 'ThirdParty')
        self.manifest()

    def mod(self, root, name, layer='42', version='1.0', require=''):
        info = root / layer / 'mod.info'
        info.parent.mkdir(parents=True, exist_ok=True)
        info.write_text(f'id={name}\nmodversion={version}\nrequire={require}\n')
        return root

    def manifest(self):
        mods = {}
        for name in ('PZSurvivorToolkit', 'PZToolkitJavaPatches'):
            root = self.package / 'mods' / name
            mods[name] = {'version': '1.0', 'files': {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}}
        (self.package / 'pack-manifest.json').write_text(json.dumps({'format': 1, 'main_revision': 'a' * 40, 'mod_ids': self.ids, 'workshop_ids': ['123', '456'], 'repository_mods': mods}))

    def run_ps(self, body):
        path = self.root / 'check.ps1'
        path.write_text(f"$env:USERPROFILE={ps(self.root)}\n. {ps(LAUNCHER)} -SourceProfile {ps(self.source)}\n" + body)
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(path)], text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout.strip())

    def resolve(self):
        return f"$r=Resolve-TrialPack {ps(self.package)} {ps(self.source)} {ps(self.workshop)}; "

    def initialize(self):
        return self.resolve() + f"Initialize-TrialProfile {ps(self.cache)} {ps(self.source)} {ps(self.package)} $r 6>$null | Out-Null; "

    def test_metadata_preserves_equals_empty_values_and_native_last_value(self):
        info = self.root / 'metadata.info'
        info.write_text('  # ignored=value\nnot metadata\n id = First \n'
                        'description=a=b=c\nrequire=\nid=Actual\n')
        result = self.run_ps(f"Read-TrialModMetadata {ps(info)} | ConvertTo-Json")
        self.assertEqual(result, {'id': 'Actual', 'description': 'a=b=c', 'require': ''})

    def test_exact_pack_ignores_stale_source_and_prefers_workshop(self):
        (self.source / 'options.ini').write_text('graphics=mine')
        self.mod(self.source / 'mods/PZSurvivorToolkit', 'PZSurvivorToolkit', version='old')
        self.mod(self.source / 'mods/Third', 'ThirdParty', version='stale')
        self.mod(self.source / 'mods/Unselected', 'Unselected')
        (self.source / 'mods/default.txt').write_text('stale selection')
        result = self.run_ps(self.initialize() + '$r.Sources | Select-Object Id,Kind,Version | ConvertTo-Json')
        self.assertEqual(next(v for v in result if v['Id'] == 'ThirdParty')['Kind'], 'Workshop')
        text = (self.cache / 'mods/default.txt').read_text()
        self.assertEqual([line.strip()[6:-1] for line in text.splitlines() if line.strip().startswith('mod = ')], self.ids + ['PZDrivingBench', 'PZDrivingOptimizerBridge'])
        self.assertEqual((self.cache / 'options.ini').read_text(), 'graphics=mine')
        self.assertEqual(sorted(p.name for p in (self.cache / 'mods').iterdir() if p.is_dir()), ['PZDrivingBench', 'PZDrivingOptimizerBridge', 'PZSurvivorToolkit', 'PZToolkitJavaPatches'])
        self.assertIn('modversion=1.0', (self.cache / 'mods/PZSurvivorToolkit/42/mod.info').read_text())

    def test_missing_mods_abort_before_profile_and_name_items(self):
        shutil.rmtree(self.workshop)
        error = self.run_ps("$e=''; try { " + self.initialize() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json")
        self.assertIn('ZombieBuddy, ThirdParty', error)
        self.assertIn('123, 456', error)
        self.assertIn('https://steamcommunity.com/sharedfiles/filedetails/?id=123', error)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_multiplayer_selects_full_pack_and_bridge_without_starter_callbacks(self):
        result = self.run_ps(f"""
$r=Resolve-TrialPack {ps(self.package)} {ps(self.source)} {ps(self.workshop)} -SessionType Multiplayer
Initialize-TrialProfile {ps(self.cache)} {ps(self.source)} {ps(self.package)} $r 6>$null | Out-Null
@{{Ids=$r.Ids;Sources=@($r.Sources.Id);Private=@($r.Private.Id)}} | ConvertTo-Json -Depth 5
""")
        self.assertEqual(result['Ids'], self.ids + ['PZDrivingOptimizerBridge'])
        self.assertIn('PZDrivingBench', result['Sources'])
        self.assertIn('PZDrivingBench', result['Private'])
        self.assertNotIn('mod = PZDrivingBench,', (self.cache / 'mods/default.txt').read_text())
        self.assertTrue((self.cache / 'mods/PZDrivingBench/42/mod.info').exists())
        # Inactive package files remain covered by the immutable private inventory.
        (self.cache / 'mods/PZDrivingBench/42/mod.info').write_text('changed')
        error = self.run_ps(f"$e=''; try {{ $r=Resolve-TrialPack {ps(self.package)} {ps(self.source)} {ps(self.workshop)} -SessionType Multiplayer; Initialize-TrialProfile {ps(self.cache)} {ps(self.source)} {ps(self.package)} $r 6>$null | Out-Null }} catch {{ $e=$_.Exception.Message }}; $e | ConvertTo-Json")
        self.assertIn('Changed mod file', error)

    def test_multiplayer_dependencies_cannot_reactivate_the_starter(self):
        self.mod(self.workshop / '456/mods/Third', 'ThirdParty', require='PZDrivingBench')
        error = self.run_ps(f"$e=''; try {{ Resolve-TrialPack {ps(self.package)} {ps(self.source)} {ps(self.workshop)} -SessionType Multiplayer | Out-Null }} catch {{ $e=$_.Exception.Message }}; $e | ConvertTo-Json")
        self.assertIn('requires unselected Mod ID PZDrivingBench', error)
        self.assertIn('PZDrivingBench', self.run_ps(self.resolve() + '$r.Ids | ConvertTo-Json'))

    def test_session_switch_refuses_to_rewrite_an_existing_exact_selection(self):
        self.run_ps(self.initialize() + '$true | ConvertTo-Json')
        original = (self.cache / 'mods/default.txt').read_text()
        error = self.run_ps(f"$e=''; try {{ $r=Resolve-TrialPack {ps(self.package)} {ps(self.source)} {ps(self.workshop)} -SessionType Multiplayer; Initialize-TrialProfile {ps(self.cache)} {ps(self.source)} {ps(self.package)} $r 6>$null | Out-Null }} catch {{ $e=$_.Exception.Message }}; $e | ConvertTo-Json")
        self.assertIn('Modified exact pack selection', error)
        self.assertEqual((self.cache / 'mods/default.txt').read_text(), original)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required')
    def test_pack_activation_checks_exact_mp_ids_and_retains_sp_starter(self):
        script = r'''
local source, expectedIds = arg[1], {'Base','PZDrivingBench','PZDrivingOptimizerBridge'}
local function check(client, actual, wanted)
    local output, callback = {}, nil
    package.loaded.PZOptimizerTrialExpectedMods = nil
    package.preload.PZOptimizerTrialExpectedMods = function() return {revision='fixture',ids=expectedIds} end
    function isClient() return client end
    function print(line) output[#output+1] = line end
    Events = {OnGameStart={Add=function(value) callback=value end}}
    function getActivatedMods()
        return {size=function() return #actual end,
            get=function(_,index) return actual[index+1] end,
            contains=function(_,id) for _,value in ipairs(actual) do if value==id then return true end end return false end}
    end
    dofile(source); callback()
    assert(#output==1 and output[1]:find(wanted,1,true), table.concat(output,'\n'))
end
check(true, {'Base','PZDrivingOptimizerBridge'}, 'pack active revision=fixture count=2')
check(true, expectedIds, 'PACK_MISMATCH missing= unexpected=PZDrivingBench')
check(true, {'PZDrivingOptimizerBridge'}, 'PACK_MISMATCH missing=Base')
check(false, expectedIds, 'pack active revision=fixture count=3')
check(false, {'Base','PZDrivingOptimizerBridge'}, 'PACK_MISMATCH missing=PZDrivingBench')
'''
        result = subprocess.run([shutil.which('luajit'), '-', str(ROOT / 'tests/optimizer_trial/PZOptimizerTrialPack.lua')],
                                input=script, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_compatible_layers_common_and_minor_selection(self):
        root = self.workshop / '456/mods/Third'
        shutil.rmtree(root)
        self.mod(root, 'Legacy', layer='legacy')
        self.mod(root, 'ThirdParty', layer='common')
        self.mod(root, 'Future', layer='42.22')
        self.assertEqual(self.run_ps(self.resolve() + "($r.Sources | Where-Object Id -eq 'ThirdParty').Info | ConvertTo-Json"), str(root / 'common/mod.info'))
        self.mod(root, 'ThirdParty', layer='42.21.9', version='current')
        result = self.run_ps(self.resolve() + "($r.Sources | Where-Object Id -eq 'ThirdParty').Version | ConvertTo-Json")
        self.assertEqual(result, 'current')

    def test_legacy_root_does_not_make_b42_mod_available(self):
        root = self.workshop / '456/mods/Third'
        shutil.rmtree(root)
        root.mkdir()
        (root / 'mod.info').write_text('id=ThirdParty')
        self.assertIn('ThirdParty', self.run_ps("$e=''; try { " + self.resolve() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json"))

    def test_local_fallback_copies_only_selected_and_detects_drift(self):
        shutil.rmtree(self.workshop / '456')
        self.mod(self.source / 'mods/Third', 'ThirdParty')
        self.mod(self.source / 'mods/Unused', 'Unused')
        self.run_ps(self.initialize() + '$true | ConvertTo-Json')
        self.assertTrue((self.cache / 'mods/ThirdParty').is_dir())
        self.assertFalse((self.cache / 'mods/Unused').exists())
        (self.cache / 'mods/ThirdParty/42/mod.info').write_text('custom')
        error = self.run_ps("$e=''; try { " + self.initialize() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json")
        self.assertIn('Changed mod file:', error)
        self.assertEqual((self.cache / 'mods/ThirdParty/42/mod.info').read_text(), 'custom')

    def test_ambiguous_roots_and_unselected_requirements_fail(self):
        other = self.mod(self.workshop / '789/mods/duplicate', 'ThirdParty')
        error = self.run_ps("$e=''; try { " + self.resolve() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json")
        self.assertIn('Ambiguous compatible mod roots', error)
        shutil.rmtree(other)
        self.mod(self.workshop / '456/mods/Third', 'ThirdParty', require='MissingDependency')
        error = self.run_ps("$e=''; try { " + self.resolve() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json")
        self.assertIn('requires unselected Mod ID MissingDependency', error)

    def test_existing_profile_reuses_settings_and_refuses_selection_package_and_private_drift(self):
        self.run_ps(self.initialize() + '$true | ConvertTo-Json')
        (self.cache / 'options.ini').write_text('user edit')
        self.run_ps(self.initialize() + '$true | ConvertTo-Json')
        self.assertEqual((self.cache / 'options.ini').read_text(), 'user edit')
        selection = self.cache / 'mods/default.txt'
        original = selection.read_text()
        selection.write_text('custom')
        error = self.run_ps("$e=''; try { " + self.initialize() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json")
        self.assertIn(str(selection), error)
        self.assertEqual(selection.read_text(), 'custom')
        selection.write_text(original)
        own = self.cache / 'mods/PZSurvivorToolkit/42/mod.info'
        own.write_text('custom')
        self.assertIn('Changed mod file', self.run_ps("$e=''; try { " + self.initialize() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json"))
        (self.package / 'mods/PZSurvivorToolkit/42/mod.info').write_text('package tamper')
        self.assertIn('Changed mod file', self.run_ps("$e=''; try { " + self.resolve() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json"))

    def test_real_b42_bridge_and_java_metadata_require_prefix_and_version(self):
        # Match the shipped Java Patches and optimizer bridge metadata convention.
        for name in ('PZToolkitJavaPatches', 'PZDrivingOptimizerBridge'):
            info = self.package / 'mods' / name / '42/mod.info'
            info.write_text('id=' + name + '\nversion=1.0\nrequire=\\ZombieBuddy\n')
        self.mod(self.workshop / '456/mods/Third', 'ThirdParty', require='\\ZombieBuddy,\\PZSurvivorToolkit')
        self.manifest()
        result = self.run_ps(self.initialize() + '$r.Sources | Select-Object Id,Version | ConvertTo-Json')
        self.assertEqual(next(v for v in result if v['Id'] == 'PZToolkitJavaPatches')['Version'], '1.0')

    def test_old_initialized_profile_refused_without_modification(self):
        marker = self.cache / '.pz-driving-bench-initialized'
        marker.write_text('CurrentMods')
        error = self.run_ps("$e=''; try { " + self.initialize() + "} catch { $e=$_.Exception.Message }; $e | ConvertTo-Json")
        self.assertIn('no current-main pack receipt', error)
        self.assertEqual(list(self.cache.iterdir()), [marker])


if __name__ == '__main__':
    unittest.main()
