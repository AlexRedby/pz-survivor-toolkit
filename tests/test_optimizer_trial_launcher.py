"""Exercise launcher parsing/guards with PowerShell; never starts Java or the game."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "tests/optimizer_trial/Launch-Trial.ps1"
PWSH = shutil.which("pwsh")
GAME_CLASSES = (
    "zombie/iso/worldgen/WorldGenUtils.class",
    "zombie/core/skinnedmodel/advancedanimation/AnimationSet.class",
)


def ps(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(PWSH, "PowerShell is needed for launcher tests")
class OptimizerTrialLauncherTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="pz optimizer trial ")
        self.base = Path(self.directory.name).resolve()
        self.addCleanup(self.directory.cleanup)

    def powershell(self, script):
        source = self.base / "test.ps1"
        source.write_text(
            "$env:USERPROFILE=" + ps(self.base) + "\n"
            ". " + ps(LAUNCHER) + " -SourceProfile " + ps(self.base / "source") + "\n"
            + script,
            encoding="utf-8",
        )
        result = subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-File", str(source)],
            text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout.strip())

    def config(self, **changes):
        config = {
            "mainClass": "zombie/gameStates/MainScreenState",
            "classpath": [".", "projectzomboid.jar"],
            "vmArgs": ["-Xms1g", "-Xmx4g", "-Djava.library.path=win64/;.", "-agentlib:zbNative"],
            "windows": {
                "6.1": {"vmArgs": ["-XX:+UseG1GC"]},
                "10.0.17134": {"vmArgs": ["-XX:+UseShenandoahGC"]},
                "11.0": {"vmArgs": ["-XX:+FutureFlag"]},
            },
        }
        config.update(changes)
        path = self.base / "ProjectZomboid64.json"
        path.write_text(json.dumps(config))
        return path

    def candidate(self, extra=None):
        selected = {GAME_CLASSES[0]: b"worldgen", GAME_CLASSES[1]: b"animation", "pzopt/Config.class": b"helper", "pzopt/build.properties": b"revision=x"}
        archive = self.base / "official.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            for name, content in selected.items():
                zipped.writestr(name, content)
            for name, content in (extra or {}).items():
                zipped.writestr(name, content)
        manifest = {
            "release_url": "https://github.com/xD3I/PZ_Optimization/releases/download/pinned/classes.zip",
            "release_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "selected_files": {name: hashlib.sha256(content).hexdigest() for name, content in selected.items()},
            "native_guards": {"zombie/Native.class": hashlib.sha256(b"native").hexdigest()},
        }
        path = self.base / "candidate-manifest.json"
        path.write_text(json.dumps(manifest))
        return archive, path

    def test_one_pc_default_and_explicit_multiplayer_mode(self):
        result = self.powershell(f"""
$default=$Session
$explicit=& {{ . {ps(LAUNCHER)} -SourceProfile {ps(self.base / 'source')} -Session Multiplayer; $Session }}
@{{Default=$default;Explicit=$explicit}} | ConvertTo-Json
""")
        self.assertEqual(result, {'Default': 'SinglePlayer', 'Explicit': 'Multiplayer'})

    def test_parse_and_greatest_applicable_windows_flags(self):
        path = self.config()
        data = self.powershell(f"$c=Read-TrialLaunchConfig {ps(path)} ([version]'10.0.22631'); $c | ConvertTo-Json -Depth 5")
        self.assertEqual(data["MainClass"], "zombie.gameStates.MainScreenState")
        self.assertEqual(data["WindowsVersion"], "10.0.17134")
        self.assertEqual(data["VmArgs"], ["-Xms1g", "-Xmx4g", "-Djava.library.path=win64/;.", "-agentlib:zbNative", "-XX:+UseShenandoahGC"])
        self.assertEqual(data["Classpath"], [".", "projectzomboid.jar"])

    def test_unknown_launcher_fields_and_non_native_main_are_rejected(self):
        for changes in ({"customArgs": []}, {"mainClass": "pzopt.AutoStart"}, {"windows": {"10.0": {"vmArgs": [], "other": True}}}, {"vmArgs": "-Xmx4g"}):
            with self.subTest(changes=changes):
                path = self.config(**changes)
                result = self.powershell(f"$rejected=$false; try {{ Read-TrialLaunchConfig {ps(path)} | Out-Null }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json")
                self.assertTrue(result)

    def test_windows_quoting_handles_spaces_quotes_and_trailing_slashes(self):
        values = ["", "-cachedir=C:\\Trial Folder\\", 'inside"quote', "plain"]
        literal = ",".join(ps(value) for value in values)
        result = self.powershell(f"@({literal}) | ForEach-Object {{ ConvertTo-WindowsArgument $_ }} | ConvertTo-Json")
        self.assertEqual(result, ['""', '"-cachedir=C:\\Trial Folder\\\\"', '"inside\\"quote"', '"plain"'])

    def test_optimized_and_control_share_base_settings_and_profile(self):
        path = self.config()
        result = self.powershell(f"""
$c=Read-TrialLaunchConfig {ps(path)} ([version]'10.0.22631')
$profile=(Read-TrialManifest {ps(ROOT / 'tests/optimizer_trial/candidate-manifest.json')}).profile
$candidate=[pscustomobject]@{{Profile=$profile;Overlay='C:\\Trial Path\\overlay';Zip='C:\\Trial Path\\official.zip'}}
$a=New-TrialPlan {ps(self.base / 'Game')} {ps(self.base / 'Trial Profile')} Optimized $c $candidate
$b=New-TrialPlan {ps(self.base / 'Game')} {ps(self.base / 'Trial Profile')} Control $c $candidate
@{{Optimized=$a;Control=$b;OriginalVm=$c.VmArgs}} | ConvertTo-Json -Depth 8
""")
        optimized, control = result["Optimized"], result["Control"]
        self.assertEqual(optimized["Cache"], control["Cache"])
        self.assertEqual(optimized["gameContextPolicy"], "BufferedWorldExitV2")
        self.assertEqual(control["gameContextPolicy"], "BufferedWorldExitV2")
        self.assertEqual(optimized["WorkingDirectory"], control["WorkingDirectory"])
        self.assertEqual(optimized["VmArgs"][:5], control["VmArgs"][:5])
        self.assertEqual(control["Classpath"], [".", "projectzomboid.jar"])
        self.assertEqual(optimized["Classpath"][1:], control["Classpath"])
        self.assertIn("-Dpz.optimizerTrial.prewarm=false", control["VmArgs"])
        profile_args = Path(optimized["OptimizerArguments"]).read_text()
        self.assertIn("-Dpzopt.instrument=false\n", profile_args)
        self.assertIn("-Dpzopt.modCompat=off\n", profile_args)
        self.assertIn("-Dpzopt.chunkHandoffDivisor=8\n", profile_args)
        self.assertIn("-Dpzopt.tileVertexDepth=true\n", profile_args)
        self.assertIn("-Dpzopt.entityUpdateParallel=false\n", profile_args)
        self.assertEqual(len(profile_args.splitlines()), 771)
        self.assertIn("@" + optimized["OptimizerArguments"], optimized["VmArgs"])
        self.assertLess(len(optimized["CommandLine"]), 32767)
        self.assertIsNone(control["OptimizerProfile"])
        self.assertIsNone(control["OptimizerArguments"])
        self.assertIn("-Dpz.optimizerTrial.sourceZip=C:\\Trial Path\\official.zip", optimized["VmArgs"])
        self.assertEqual(len(result["OriginalVm"]), 5)

    def test_extended_profile_rejects_argument_injection(self):
        for value in ("true\n-javaagent:foreign.jar", '" -Xmx1g', "true # comment"):
            profile = json.loads((ROOT / 'tests/optimizer_trial/candidate-manifest.json').read_text())['profile']
            profile['properties']['enabled'] = value
            text = json.dumps(profile)
            self.assertTrue(self.powershell(f"$p={ps(text)} | ConvertFrom-Json; $bad=$false; try {{ Write-TrialOptimizerArguments {ps(self.base / 'cache')} $p | Out-Null }} catch {{ $bad=$true }}; $bad | ConvertTo-Json"))

    def test_extended_profile_rejects_unknown_additional_pin(self):
        profile = json.loads((ROOT / 'tests/optimizer_trial/candidate-manifest.json').read_text())['profile']
        profile['properties']['unreviewedFutureFlag'] = 'true'
        text = json.dumps(profile)
        self.assertTrue(self.powershell(f"$p={ps(text)} | ConvertFrom-Json; $bad=$false; try {{ Write-TrialOptimizerArguments {ps(self.base / 'cache')} $p | Out-Null }} catch {{ $bad=$_.Exception.Message -match 'inventory' }}; $bad | ConvertTo-Json"))

    def test_added_resources_must_be_absent_in_original_classpath(self):
        game = self.base / "game"
        game.mkdir()
        name = 'zombie/iso/IsoChunkMap$1.class'
        with zipfile.ZipFile(game / 'stock.jar', 'w') as z:
            z.writestr('zombie/iso/IsoChunkMap.class', b'stock')
        with zipfile.ZipFile(game / 'foreign.jar', 'w') as z:
            z.writestr(name, b'foreign')
        self.assertTrue(self.powershell(f"Assert-TrialNativeAbsences {ps(game)} @('stock.jar') @({ps(name)}); $true | ConvertTo-Json"))
        self.assertTrue(self.powershell(f"$bad=$false; try {{ Assert-TrialNativeAbsences {ps(game)} @('stock.jar','foreign.jar') @({ps(name)}) }} catch {{ $bad=$true }}; $bad | ConvertTo-Json"))

    def test_windows_ready_requires_actual_tile_batch_gate(self):
        text = self.readiness_text().replace('tileBatch=true', 'tileBatch=false')
        self.assertFalse(self.powershell(f"Get-TrialReadiness {ps(text)} | ConvertTo-Json -Depth 5")['Ready'])

    def test_extracts_only_manifest_files_and_rejects_extra_overlay_content(self):
        archive, manifest = self.candidate({"pzopt/Uninstall.ps1": b"do not execute", "media/lua/foreign.lua": b"no"})
        overlay = self.base / "overlay"
        result = self.powershell(f"$m=Read-TrialManifest {ps(manifest)}; Expand-TrialCandidate {ps(archive)} {ps(overlay)} $m; @(Get-ChildItem -LiteralPath {ps(overlay)} -Recurse -File).Count | ConvertTo-Json")
        self.assertEqual(result, 4)
        self.assertFalse((overlay / "pzopt/Uninstall.ps1").exists())
        (overlay / "extra.class").write_bytes(b"foreign")
        self.assertTrue(self.powershell(f"$m=Read-TrialManifest {ps(manifest)}; $rejected=$false; try {{ Expand-TrialCandidate {ps(archive)} {ps(overlay)} $m }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))

    def test_archive_traversal_symlink_and_wrong_zip_hash_are_rejected(self):
        for kind in ("traversal", "symlink", "hash"):
            with self.subTest(kind=kind):
                archive, manifest_path = self.candidate()
                manifest = json.loads(manifest_path.read_text())
                if kind != "hash":
                    with zipfile.ZipFile(archive, "a") as zipped:
                        if kind == "traversal":
                            zipped.writestr("../outside", b"bad")
                        else:
                            entry = zipfile.ZipInfo("link")
                            entry.create_system = 3
                            entry.external_attr = 0o120777 << 16
                            zipped.writestr(entry, "target")
                    manifest["release_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
                else:
                    manifest["release_sha256"] = "0" * 64
                manifest_path.write_text(json.dumps(manifest))
                self.assertTrue(self.powershell(f"$m=Read-TrialManifest {ps(manifest_path)}; $rejected=$false; try {{ Expand-TrialCandidate {ps(archive)} {ps(self.base / ('overlay-' + kind))} $m }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))

    def test_native_guard_checks_actual_jar_entries(self):
        _, manifest = self.candidate()
        jar = self.base / "native.jar"
        with zipfile.ZipFile(jar, "w") as zipped:
            zipped.writestr("zombie/Native.class", b"native")
        self.assertTrue(self.powershell(f"$m=Read-TrialManifest {ps(manifest)}; Assert-TrialNativeGuards {ps(jar)} $m.native_guards; $true | ConvertTo-Json"))
        with zipfile.ZipFile(jar, "w") as zipped:
            zipped.writestr("zombie/Native.class", b"modified")
        self.assertTrue(self.powershell(f"$m=Read-TrialManifest {ps(manifest)}; $rejected=$false; try {{ Assert-TrialNativeGuards {ps(jar)} $m.native_guards }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))

    def test_game_preflight_preserves_native_loader_and_refuses_overrides(self):
        game = self.base / "game"
        for name in ("projectzomboid.jar", "ZombieBuddy.jar", "zbNative.dll", "jre64/bin/java.exe"):
            target = game / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"fixture")
        path = self.config()
        data = self.powershell(f"$c=Read-TrialLaunchConfig {ps(path)} ([version]'10.0.22631'); Assert-TrialGame {ps(game)} $c; $c.VmArgs | ConvertTo-Json")
        self.assertIn("-Xmx4g", data)
        self.assertIn("-XX:+UseShenandoahGC", data)
        self.assertEqual(data.count("-agentlib:zbNative"), 1)
        self.assertFalse(any(arg.startswith("-javaagent:") for arg in data))
        override = game / "zombie/GameWindow.class"
        override.parent.mkdir()
        override.write_bytes(b"foreign")
        self.assertTrue(self.powershell(f"$c=Read-TrialLaunchConfig {ps(path)}; $rejected=$false; try {{ Assert-TrialGame {ps(game)} $c }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))
        override.unlink()
        path = self.config(vmArgs=["-javaagent:foreign.jar"])
        self.assertTrue(self.powershell(f"$c=Read-TrialLaunchConfig {ps(path)}; $rejected=$false; try {{ Assert-TrialGame {ps(game)} $c }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))

    def test_zombiebuddy_native_java_path_and_missing_loader_modes(self):
        game = self.base / "game"
        for name in ("projectzomboid.jar", "ZombieBuddy.jar", "zbNative.dll", "jre64/bin/java.exe"):
            target = game / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"fixture")
        cases = [[], ["-agentlib:zbNative=policy=deny-new"], ["-agentpath:" + str(game / "zbNative.dll") + "=verbosity=1"], ["-javaagent:ZombieBuddy.jar=policy=deny-new"]]
        for args in cases:
            with self.subTest(args=args):
                path = self.config(vmArgs=["-Xmx4g"] + args, windows={})
                result = self.powershell(f"$c=Read-TrialLaunchConfig {ps(path)}; Assert-TrialGame {ps(game)} $c; $c.VmArgs | ConvertTo-Json")
                self.assertEqual(result, ["-Xmx4g"] + (args or ["-agentlib:zbNative"]))
        path = self.config(vmArgs=["-agentlib:zbNative", "-javaagent:ZombieBuddy.jar"])
        self.assertTrue(self.powershell(f"$c=Read-TrialLaunchConfig {ps(path)}; $rejected=$false; try {{ Assert-TrialGame {ps(game)} $c }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))
        (game / "zbNative.dll").unlink()
        path = self.config(vmArgs=["-Xmx4g"])
        self.assertTrue(self.powershell(f"$c=Read-TrialLaunchConfig {ps(path)}; $rejected=$false; try {{ Assert-TrialGame {ps(game)} $c }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))

    def test_actual_windows_version_comes_from_cim_and_probe_failure_is_not_guessed(self):
        result = self.powershell("function Get-CimInstance { [CmdletBinding()] param([string]$ClassName); [pscustomobject]@{Version='10.0.22631'} }; (Get-TrialWindowsVersion).ToString() | ConvertTo-Json")
        self.assertEqual(result, "10.0.22631")
        self.assertTrue(self.powershell("function Get-CimInstance { throw 'probe unavailable' }; $rejected=$false; try { Get-TrialWindowsVersion | Out-Null } catch { $rejected=$true }; $rejected | ConvertTo-Json"))

    def test_multiplayer_plan_and_readiness_require_post_connection_lifecycle(self):
        path = self.config()
        base = self.readiness_text().replace('mode=singleplayer', 'mode=multiplayer')
        result = self.powershell(f"""
$c=Read-TrialLaunchConfig {ps(path)}
$profile=(Read-TrialManifest {ps(ROOT / 'tests/optimizer_trial/candidate-manifest.json')}).profile
$candidate=[pscustomobject]@{{Profile=$profile;Overlay='C:\\Trial Path\\overlay';Zip='C:\\Trial Path\\official.zip'}}
$p=New-TrialPlan {ps(self.base / 'Game')} {ps(self.base / 'Trial Profile')} Optimized $c $candidate -SessionType Multiplayer
$early=Get-TrialReadiness {ps(base)} -SessionType Multiplayer
$ready=Get-TrialReadiness ({ps(base)}+"`n[OptimizerTrial] bridge ready mode=multiplayer client=true server=false session=1`n[OptimizerTrial] animal drain invoked mode=multiplayer client=true server=false") -SessionType Multiplayer
@{{Plan=$p;Early=$early;Ready=$ready}} | ConvertTo-Json -Depth 8
""")
        self.assertEqual(result['Plan']['Session'], 'Multiplayer')
        self.assertIn('-Dpz.optimizerTrial.mode=multiplayer', result['Plan']['VmArgs'])
        self.assertIn('-Dpz.optimizerTrial.overlay=C:\\Trial Path\\overlay', result['Plan']['VmArgs'])
        self.assertFalse(result['Early']['Ready'])
        self.assertTrue(result['Ready']['Ready'])

    def test_live_and_final_readiness_share_exact_multiplayer_context_and_failures(self):
        revision = 'a' * 40
        context = 'PZDrivingBench-OptimizerTrial-MP-' + 'b' * 32
        pack = f'[OptimizerTrial] pack active revision={revision} count=68\n[PZToolkitJavaPatches] Experimental B42.21 patch:'
        control = pack + '\n[OptimizerTrial] bridge inactive: explicit opt-in absent'
        optimized = pack + '\n' + self.readiness_text().replace('mode=singleplayer', 'mode=multiplayer') + (
            '\n[OptimizerTrial] bridge ready mode=multiplayer client=true server=false session=1'
            '\n[OptimizerTrial] animal drain invoked mode=multiplayer client=true server=false')
        context_line = '\n[OptimizerTrial] multiplayer context ready world=' + context
        cases = []
        for mode, text in (('Optimized', optimized), ('Control', control)):
            cases.extend([
                (mode, text + context_line, False, True, False),
                (mode, text, False, False, False),
                (mode, text + context_line + 'stale', False, False, False),
                (mode, text + context_line, True, False, True),
                (mode, text + context_line + '\n[PZDrivingBench] FAIL timeout', False, False, True),
                (mode, text + context_line + '\n[OptimizerTrial] drive telemetry disabled error=fixture', False, False, True),
                (mode, text + context_line + '\n[OptimizerTrial] telemetry flush failed reason=Disconnect error=fixture', False, False, True),
                (mode, text + context_line + '\n[OptimizerTrial] prewarm disabled: native lifecycle changed', False, False, True),
            ])
        cases.append(('Control', pack + context_line, False, False, False))
        calls = ',\n'.join(
            '(Get-TrialRunReadiness ' + ps(text) + ' ' + mode + ' ' + ps(revision)
            + ' 68 Multiplayer -ContextId ' + ps(context) + ' -PreviousFailure $' + str(prior).lower() + ')'
            for mode, text, prior, _, _ in cases)
        result = self.powershell('@(' + calls + ') | ConvertTo-Json -Depth 5')
        for state, (_, _, _, ready, failed) in zip(result, cases):
            self.assertEqual(state['Ready'], ready, state)
            self.assertEqual(state['Failed'], failed, state)

    def test_final_classification_uses_live_readiness_helper_with_prior_failure(self):
        source = LAUNCHER.read_text()
        self.assertEqual(source.count('= Get-TrialRunReadiness '), 2)
        self.assertEqual(source.count('-PreviousFailure $failureAnnounced'), 2)
        final = source[source.index('$plan.JavaExitCode = $process.ExitCode'):]
        self.assertNotIn('$plan.Readiness = Get-TrialReadiness ', final)
        self.assertNotIn('$plan.Readiness = Get-TrialPackActivation ', final)

    def test_launch_log_local_does_not_shadow_session_parameter(self):
        # PowerShell identifiers are case-insensitive: $session used to replace
        # the requested $Session mode with a log descriptor after launching Java.
        result = self.powershell(f"""
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile({ps(LAUNCHER)},[ref]$tokens,[ref]$errors)
$writes=@($ast.FindAll({{param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -ieq 'Session'}}, $true))
$writes.Count | ConvertTo-Json
""")
        self.assertEqual(result, 0)

    def readiness_text(self):
        return "\n".join([
            "[OptimizerTrial] prewarm armed; awaiting OnGameBoot; mode=singleplayer",
            "[OptimizerTrial] official cache and preload active",
            "[OptimizerTrial] tile batch used starts=10 merged=20 stamped=30",
            "[OptimizerTrial] bake scheduler used frames=1 grants=10",
            "[OptimizerTrial] extended active profile=xd3i-b42.21-d1bbdcf-bounded-v1 tileBatch=true bakeScheduler=true occlusionRetain=true chunkHandoffDivisor=8",
            "[OptimizerTrial] OnGameBoot animation preload started",
            "[pzopt] anim sets preloaded in 1.23 s",
            "[OptimizerTrial] animation preload joined; animal preload started",
            "[pzopt] animalPreload: 12 animation sets, 6 action groups parsed in 0.5 s",
            "[pzopt] animalPreload: 4 action groups handed to the game, 2 it had loaded first",
        ])

    def test_readiness_requires_all_stages_and_latest_complete_handoff(self):
        good = self.readiness_text()
        variants = [
            good,
            good.replace("[OptimizerTrial] official cache and preload active", ""),
            good.replace("[pzopt] animalPreload: 12 animation sets, 6 action groups parsed in 0.5 s", ""),
            good + "\n[pzopt] animalPreload: 1 action groups handed to the game, 2 it had loaded first",
            good + "\n[OptimizerTrial] prewarm disabled: runtime gate failed",
            "Java mod PZDrivingOptimizerBridge denied",
            good.replace("1.23", "1,23"),
            good.replace("merged=20", "merged=0"),
        ]
        literal = ",".join(ps(text) for text in variants)
        states = self.powershell(f"@({literal}) | ForEach-Object {{ Get-TrialReadiness $_ }} | ConvertTo-Json -Depth 6")
        self.assertEqual([state["Ready"] for state in states], [True, False, False, False, False, False, True, False])
        self.assertEqual(states[0]["HandedOff"], 6)
        self.assertEqual(states[3]["HandedOff"], 3)
        self.assertTrue(states[4]["Failed"])
        self.assertTrue(states[5]["Failed"])

    def test_stale_console_never_satisfies_fresh_session_readiness(self):
        cache = self.base / "cache"
        cache.mkdir()
        (cache / "console.txt").write_text(self.readiness_text())
        state = self.powershell(f"$logs=New-TrialSessionLogs {ps(cache)}; $state=Get-TrialReadiness (Read-TrialSessionText $logs); @{{State=$state;Logs=$logs}} | ConvertTo-Json -Depth 7")
        self.assertFalse(state["State"]["Ready"])
        logs = state["Logs"]
        self.assertFalse(Path(logs["Console"]).exists())
        self.assertEqual((Path(logs["Directory"]) / "previous-console.txt").read_text(), self.readiness_text())
        Path(logs["Stdout"]).write_text(self.readiness_text())
        states = self.powershell(f"$logs={ps(json.dumps(logs))} | ConvertFrom-Json; Get-TrialReadiness (Read-TrialSessionText $logs) | ConvertTo-Json -Depth 6")
        self.assertTrue(states["Ready"])

    def test_world_readiness_does_not_require_context_console_writes(self):
        texts = ["[PZDrivingBench] READY driver=true engine=true x=1 y=2",
                 "[OptimizerTrial] drive sample tsMs=10000 inVehicle=true speedKmh=10",
                 "[PZDrivingBench] READY driver=false engine=true", ""]
        literal = ",".join(ps(text) for text in texts)
        states = self.powershell(f"@({literal}) | ForEach-Object {{ Test-TrialWorldReady $_ }} | ConvertTo-Json")
        self.assertEqual(states, [True, False, False, False])

    def test_trial_world_marker_is_accepted_by_both_real_lua_consumers(self):
        lua = shutil.which("luajit") or shutil.which("lua")
        if not lua:
            self.skipTest("Lua is needed for cross-consumer marker check")
        run = self.powershell("New-TrialRunName | ConvertTo-Json")
        self.assertTrue(run.startswith("PZDrivingBench-OptimizerTrial-"))
        self.assertLessEqual(len(run), 100)
        script = self.base / "marker.lua"
        script.write_text("""
local run,starter,fixture=arg[1],arg[2],arg[3]
local menu,draw,chosen
Events={OnMainMenuEnter={Add=function(f) menu=f end},OnPreUIDraw={Add=function(f) draw=f end}}
isClient=function() return false end; isServer=function() return false end
isIngameState=function() return false end
getFileReader=function() return {readLine=function() return run end,close=function() end} end
local world={setGameMode=function() end,setWorld=function(_,name) chosen=name end,setMap=function() end,getWorld=function() return run end}
getWorld=function() return world end
-- The starter reaches setWorld before character-creation UI, which is outside this focused test.
dofile(starter); menu(); draw(); assert(chosen==run,'starter rejected marker')
local F=dofile(fixture); assert(F.allowed(),'fixture rejected world')
""")
        base = ROOT / "tests/driving_benchmark/mods/PZDrivingBench/42/media/lua"
        result = subprocess.run([lua, str(script), run, str(base / "client/DrivingBenchStart.lua"), str(base / "shared/DrivingBenchFixture.lua")], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_effective_classpath_rejects_innocuously_named_shadow_jar(self):
        _, manifest = self.candidate()
        game = self.base / "game"
        game.mkdir()
        for filename, content in (("custom.jar", b"modified"), ("projectzomboid.jar", b"native")):
            with zipfile.ZipFile(game / filename, "w") as zipped:
                zipped.writestr("zombie/Native.class", content)
        state = self.powershell(f"$m=Read-TrialManifest {ps(manifest)}; $rejected=$false; try {{ Assert-TrialClasspathGuards {ps(game)} @('custom.jar','projectzomboid.jar') $m.native_guards }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json")
        self.assertTrue(state)
        self.assertTrue(self.powershell(f"$m=Read-TrialManifest {ps(manifest)}; Assert-TrialClasspathGuards {ps(game)} @('projectzomboid.jar','custom.jar') $m.native_guards; $true | ConvertTo-Json"))

    def test_readiness_requires_expected_main_pack_and_java_activation(self):
        revision = 'a' * 40
        # Match the native log prefix emitted around Lua print(), not a bare marker.
        marker = 'LOG  : Lua          f:0> [OptimizerTrial] pack active revision=' + revision + ' count=72'
        java = '[PZToolkitJavaPatches] Experimental B42.21 patch: vehicle patch ready'
        good = self.readiness_text() + '\n' + marker + '\n' + java
        variants = [good, good.replace(marker, ''), good.replace(revision, 'b' * 40), good.replace(java, ''), good.replace('count=72', 'count=69'), good + '\n[OptimizerTrial] PACK_MISMATCH missing=ThirdParty unexpected=', good + '\nJava mod PZToolkitJavaPatches denied', good + '\nZombieBuddy denied Java mod PZToolkitJavaPatches']
        literal = ','.join(ps(text) for text in variants)
        results = self.powershell(f"@({literal}) | ForEach-Object {{ @{{Optimized=(Get-TrialReadiness $_ {ps(revision)} 72);Control=(Get-TrialPackActivation $_ {ps(revision)} 72)}} }} | ConvertTo-Json -Depth 6")
        for index, result in enumerate(results):
            with self.subTest(index=index):
                for mode in ('Optimized', 'Control'):
                    self.assertEqual(result[mode]['Ready'], index == 0)
                if index >= 5:
                    self.assertTrue(result['Control']['Failed'])
                    self.assertTrue(result['Optimized']['Failed'])
        # Existing callers keep the current 69-mod default.
        default_text = good.replace('count=72', 'count=69')
        default = self.powershell(f"Get-TrialReadiness {ps(default_text)} {ps(revision)} | ConvertTo-Json -Depth 5")
        self.assertTrue(default['Ready'])

    def test_inherited_java_and_optimizer_harness_are_rejected(self):
        self.assertTrue(self.powershell("$env:JAVA_TOOL_OPTIONS='-Xmx8g'; $rejected=$false; try { Assert-TrialEnvironment } catch { $rejected=$true }; $rejected | ConvertTo-Json"))
        for name in ("Lua/pzopt-harness.txt", "pzopt/benchmark/plan.properties", "pzopt.properties"):
            target = self.base / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("foreign")
            self.assertTrue(self.powershell(f"$rejected=$false; try {{ Assert-TrialNoHarness {ps(self.base)} }} catch {{ $rejected=$true }}; $rejected | ConvertTo-Json"))
            target.unlink()


if __name__ == "__main__":
    unittest.main()
