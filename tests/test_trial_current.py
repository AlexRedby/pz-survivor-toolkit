"""Current upstream Windows launch policy, exercised with pwsh on macOS."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')


def ps(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(PWSH, 'PowerShell required')
class CurrentTrialTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='pz current trial ')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.agent = self.base / 'TrialProbe.jar'
        self.agent.write_bytes(b'comparison probe fixture')
        self.manifest = {
            'format': 1, 'game_version': '42.22.2',
            'upstream_revision': 'fad5786285a0b9c28ed804544ce01ba49fc5f197',
            'release_url': 'https://github.com/xD3I/PZ_Optimization/releases/download/pinned/classes.zip',
            'release_sha256': 'ba125a3f05cc04617c3f49217e1f07e99efe3dfa0ddaa4f34beb5020f35973c4',
            'release_size': 35562840,
            'native_guards': {'zombie/Native.class': 'a' * 64},
            'selected_files': {'pzopt/agent/pzopt-agent.jar': 'b' * 64,
                               'pzopt/overrides/zombie/Native.class': 'c' * 64},
            'runtime': {'kind': 'javaagent', 'path': 'pzopt/agent/pzopt-agent.jar',
                        'properties': {'enabled': 'true'},
                        'ready_markers': ['[pzopt] reviewed runtime ready']},
        }
        self.path = self.base / 'current-trial-manifest.json'
        self.path.write_text(json.dumps(self.manifest))
        (self.base / 'build-receipt.json').write_text(json.dumps({
            'trial_probe_sha256': hashlib.sha256(self.agent.read_bytes()).hexdigest(),
            'candidate_manifest_sha256': hashlib.sha256(self.path.read_bytes()).hexdigest()}))

    def run_ps(self, body):
        script = self.base / 'check.ps1'
        script.write_text(f"$env:USERPROFILE={ps(self.base)}\n"
                          f". {ps(ROOT / 'tests/optimizer_trial/Launch-Trial.ps1')} -SourceProfile {ps(self.base / 'source')}\n"
                          + body)
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(script)],
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout.strip())

    def test_pinned_manifest_selects_current_mod_layer(self):
        mod = self.base / 'mod'
        for layer in ('42', '42.21', '42.22', '42.23'):
            info = mod / layer / 'mod.info'
            info.parent.mkdir(parents=True)
            info.write_text(f'id=Current\nmodversion={layer}\n')
        result = self.run_ps(f"$m=Read-CurrentTrialManifest {ps(self.path)}; (Get-TrialModInfo {ps(mod)}).Info | ConvertTo-Json")
        self.assertEqual(Path(result), mod / '42.22/mod.info')

    def test_rejects_old_or_unsafe_runtime_manifest(self):
        cases = [dict(game_version='42.21'), dict(upstream_revision='d1bbdcf'),
                 dict(selected_files={'../pzopt/Config.class': 'a' * 64}),
                 dict(runtime={**self.manifest['runtime'], 'properties': {'java.class.path': 'evil'}})]
        for changes in cases:
            with self.subTest(changes=changes):
                self.path.write_text(json.dumps({**self.manifest, **changes}))
                self.assertTrue(self.run_ps(f"$rejected=$false; try {{ Read-CurrentTrialManifest {ps(self.path)} | Out-Null }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))

    def test_optimized_premain_order_control_native_classpath_and_isolated_home(self):
        result = self.run_ps(fr"""
$m=Read-CurrentTrialManifest {ps(self.path)}
$c=[pscustomobject]@{{VmArgs=@('-Xmx4g','-agentlib:zbNative=retained=option');Classpath=@('.','projectzomboid.jar');MainClass='zombie.gameStates.MainScreenState';WindowsVersion='10.0'}}
$candidate=[pscustomobject]@{{Agent='C:\Trial Runtime\pzopt\agent\pzopt-agent.jar';Root='C:\Trial Runtime';Zip='C:\official.zip'}}
$root={ps(self.base / 'Profiles/OptimizerTrial')}
$a=New-CurrentTrialPlan {ps(self.base / 'Game')} (Get-CurrentTrialCache $root Optimized) Optimized $c $candidate SinglePlayer $m {ps(self.base)}
$b=New-CurrentTrialPlan {ps(self.base / 'Game')} (Get-CurrentTrialCache $root Control Multiplayer) Control $c $null Multiplayer $m {ps(self.base)}
@{{Optimized=$a;Control=$b;Original=$c;JavaToolOptions=$env:JAVA_TOOL_OPTIONS}} | ConvertTo-Json -Depth 12
""")
        a, b = result['Optimized'], result['Control']
        self.assertNotEqual(a['Cache'], b['Cache'])
        self.assertEqual(Path(a['Cache']).parent.name, 'SinglePlayer')
        self.assertEqual(Path(b['Cache']).parent.name, 'Multiplayer')
        self.assertEqual(a['VmArgs'][0], '-javaagent:C:\\Trial Runtime\\pzopt\\agent\\pzopt-agent.jar')
        self.assertEqual(a['VmArgs'][1], '-javaagent:' + str(self.agent))
        self.assertEqual(b['VmArgs'][0], '-javaagent:' + str(self.agent))
        self.assertIn('-agentlib:zbNative=retained=option', a['VmArgs'])
        self.assertIn('-agentlib:zbNative=retained=option', b['VmArgs'])
        self.assertEqual(b['Classpath'], result['Original']['Classpath'])
        self.assertEqual(a['Classpath'][:-1], b['Classpath'])
        self.assertFalse(any('overrides' in value for value in a['Classpath']))
        self.assertIn('-Dpz.optimizerTrial.arm=Optimized', a['VmArgs'])
        self.assertIn('-Dpz.optimizerTrial.arm=Control', b['VmArgs'])
        self.assertFalse(any(value.startswith('-Dpzopt.') or value.startswith('@') for value in b['VmArgs']))
        self.assertEqual(Path(a['OptimizerArguments']).read_text(), '-Dpzopt.enabled=true\n')
        self.assertIn('-Duser.home=' + str(Path(a['Cache']) / 'RuntimeHome'), a['VmArgs'])
        self.assertIsNone(result['JavaToolOptions'])

    def test_current_metadata_admission_rejects_stale_max_but_ignores_patch_suffix(self):
        result = self.run_ps("""
$script:TrialGameVersion=[version]'42.22.2'
$mod=[pscustomobject]@{Id='Fixture';Info='fixture/mod.info';Metadata=@{versionMin='42.22.9';versionMax='42.22'}}
Assert-TrialCurrentModCompatibility $mod
$mod.Metadata.versionMax='42.21'
$rejected=$false; try { Assert-TrialCurrentModCompatibility $mod } catch { $rejected=$true }
$rejected | ConvertTo-Json
""")
        self.assertTrue(result)

    def test_probe_mutation_is_rejected(self):
        self.agent.write_bytes(b'changed')
        self.assertTrue(self.run_ps(f"$rejected=$false; try {{ Get-CurrentTrialProbe {ps(self.base)} | Out-Null }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))

    def test_readiness_requires_effective_classes_bridge_pack_and_session(self):
        log = '\n'.join(['[OptimizerTrial] pack active revision=' + 'd' * 40 + ' count=4',
                         '[PZToolkitJavaPatches] Experimental B42.22.2 patch: zombie=true',
                         '[OptimizerTrial] current bridge ready mode=Optimized',
                         '[OptimizerTrial] effective classes verified mode=Optimized',
                         '[pzopt] reviewed runtime ready', '[PZDrivingBench] READY driver=true engine=true'])
        body = f"$m=Read-CurrentTrialManifest {ps(self.path)}; $text={ps(log)}; "
        result = self.run_ps(body + f"@{{Ready=(Get-CurrentTrialReadiness $text Optimized {'d' * 40} 4 SinglePlayer '' -PreviousFailure $false -Manifest $m); MissingProbe=(Get-CurrentTrialReadiness ($text.Replace('[OptimizerTrial] effective classes verified mode=Optimized','')) Optimized {'d' * 40} 4 SinglePlayer '' -PreviousFailure $false -Manifest $m); WrongMode=(Get-CurrentTrialReadiness $text Control {'d' * 40} 4 SinglePlayer '' -PreviousFailure $false -Manifest $m); HostPending=(Get-CurrentTrialReadiness $text Optimized {'d' * 40} 4 Multiplayer 'context' -PreviousFailure $false -Manifest $m); Failed=(Get-CurrentTrialReadiness ($text + '[OptimizerTrial] effective classes failed') Optimized {'d' * 40} 4 SinglePlayer '' -PreviousFailure $false -Manifest $m)}} | ConvertTo-Json -Depth 6")
        self.assertTrue(result['Ready']['Ready'])
        for name in ('MissingProbe', 'WrongMode', 'HostPending', 'Failed'):
            self.assertFalse(result[name]['Ready'], name)
        self.assertTrue(result['Failed']['Failed'])

    def test_mode_console_remains_isolated_and_receipts_share_collector_root(self):
        cache = self.base / 'Profiles/OptimizerTrial/Optimized'
        cache.mkdir(parents=True)
        (cache / 'console.txt').write_text('previous session')
        root = cache.parent
        result = self.run_ps(f"New-TrialSessionLogs {ps(cache)} -RunRoot {ps(root)} | ConvertTo-Json")
        self.assertEqual(Path(result['Console']), cache / 'console.txt')
        self.assertEqual(Path(result['Directory']).parent, root / 'TrialRuns')
        self.assertEqual((Path(result['Directory']) / 'previous-console.txt').read_text(), 'previous session')


if __name__ == '__main__':
    unittest.main()
