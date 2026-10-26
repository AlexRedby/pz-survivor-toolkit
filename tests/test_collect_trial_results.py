"""Fixture-only results collector checks; no game, JFR tools or external captures."""
import hashlib
import json
from datetime import datetime
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parent / "optimizer_trial" / "Collect-TrialResults.ps1"
PWSH = shutil.which("pwsh")


@unittest.skipUnless(PWSH, "PowerShell is unavailable")
class TrialResultsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pz-results-", dir="/private/tmp" if Path("/private/tmp").is_dir() else None)
        self.root = Path(self.temp.name).resolve()
        self.runs = self.root / "Profiles" / "OptimizerTrial" / "TrialRuns"
        self.runs.mkdir(parents=True)
        self.control = self.root / "control capture.json"
        self.optimized = self.root / "optimized capture.json"
        self.control.write_text(json.dumps({"CaptureData": {"MsBetweenPresents": [7.0, 9.0]}}))
        self.optimized.write_text(json.dumps({"Runs": [{"CaptureData": {"FrametimeMs": [8.0, 10.0]}}]}))
        for name in ("pack-manifest.json", "build-receipt.json", "candidate-manifest.json"):
            (self.root / name).write_text("{}")
        (self.root / "verification.txt").write_text("fixture only")
        self.run_fixture("Control", "control-run", "2026-10-20T10:00:00Z")
        self.run_fixture("Optimized", "optimized-run", "2026-10-20T11:00:00Z")

    def tearDown(self):
        self.temp.cleanup()

    def run_fixture(self, mode, name, start, *, closed=True, complete=True):
        directory = self.runs / name
        directory.mkdir()
        receipt = {"Mode": mode, "Pid": 2147483000, "ProcessStartUtc": start,
                   "JavaExitCode": 0 if closed else None, "FinishedUtc": "2026-10-22T10:00:00Z" if closed else None,
                   "Activation": "Verified" if mode == "Optimized" else "ControlVerified"}
        (directory / "launch.json").write_text(json.dumps(receipt))
        (directory / "diagnostics.json").write_text(json.dumps({"format": 1, "mode": mode, "targetPid": receipt["Pid"],
            "processStartUtc": start, "status": "Complete" if complete else "Incomplete", "jfrFile": "JFR/drive.jfr"}))
        for name in ("telemetry.jsonl", "hardware.json", "game-options.ini", "session-console.txt", "stdout.txt", "stderr.txt"):
            (directory / name).write_text("fixture\n")
        (directory / "JFR").mkdir()
        (directory / "JFR" / "drive.jfr").write_bytes(b"fixture recording")
        (directory / "JFR" / "capture.json").write_text("{}")
        (directory / "JFR" / "summary.txt").write_text("fixture summary")
        (directory / "JVM").mkdir()
        for name in ("VM-version.txt", "VM-flags.txt", "VM-command_line.txt", "GC-heap_info.txt"):
            (directory / "JVM" / name).write_text("fixture JVM snapshot")
        return directory

    def collect(self, before="", *, expect_success=True, automatic=False):
        env = dict(os.environ, PZ_COLLECT_SCRIPT=str(SCRIPT), PZ_COLLECT_ROOT=str(self.root),
                   PZ_CONTROL=str(self.control), PZ_OPTIMIZED=str(self.optimized))
        capture_args = "" if automatic else " -ControlCapture $env:PZ_CONTROL -OptimizedCapture $env:PZ_OPTIMIZED"
        command = ". $env:PZ_COLLECT_SCRIPT; " + before + "; try { $r = New-TrialResultsBundle -PackageRoot $env:PZ_COLLECT_ROOT" + capture_args + "; $r | ConvertTo-Json -Depth 20 -Compress } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }"
        result = subprocess.run([PWSH, "-NoLogo", "-NoProfile", "-Command", command], env=env, text=True, capture_output=True)
        if expect_success:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def automatic_fixture(self, mode, run_name=None):
        run = self.runs / (run_name or (mode.lower() + "-run"))
        launch = json.loads((run / "launch.json").read_text())
        launch["automaticCapFrameX"] = True
        (run / "launch.json").write_text(json.dumps(launch))
        capture_directory = run / "CapFrameX"
        capture_directory.mkdir(exist_ok=True)
        source = self.control if mode == "Control" else self.optimized
        capture = capture_directory / ("CapFrameX-java-20261020-" + mode + ".json")
        capture.write_bytes(source.read_bytes())
        csv = capture.with_suffix(".json.csv")
        csv.write_text("MsBetweenPresents\n7\n9\n" if mode == "Control" else "MsBetweenPresents\n8\n10\n")
        wrapper = {"format": 1, "status": "Complete", "mode": mode, "targetPid": launch["Pid"],
                   "triggeredUtc": "2026-10-20T12:00:00Z",
                   "request": {"directory": str(capture_directory), "token": "fixture-" + mode,
                               "targetPid": launch["Pid"], "processName": "java", "seconds": 90,
                               "requestedUtc": "2026-10-20T12:00:00Z", "acknowledgedUtc": "2026-10-20T12:00:01Z"},
                   "result": {"Json": str(capture), "Csv": str(csv), "DurationSeconds": 90,
                              "FrameCount": 2, "CsvFrameCount": 2,
                              "JsonSha256": hashlib.sha256(capture.read_bytes()).hexdigest(),
                              "CsvSha256": hashlib.sha256(csv.read_bytes()).hexdigest()}}
        (run / "frame-capture.json").write_text(json.dumps(wrapper))
        return run, wrapper

    def buffered_context_fixture(self, mode, *, world=None, reason="PostSaveExit"):
        run = self.runs / (mode.lower() + "-run")
        launch_path = run / "launch.json"
        launch = json.loads(launch_path.read_text())
        world = world or "PZDrivingBench-OptimizerTrial-" + mode
        launch.update(gameContextPolicy="BufferedWorldExitV2", TrialWorld=world)
        launch_path.write_text(json.dumps(launch))
        diagnostic_path = run / "diagnostics.json"
        diagnostic = json.loads(diagnostic_path.read_text())
        diagnostic.update(frameRequestedUtc="2026-10-20T12:00:00Z",
                          frameAcknowledgedUtc="2026-10-20T12:00:01Z", capFrameXSeconds=90)
        diagnostic_path.write_text(json.dumps(diagnostic))
        epoch = int(datetime.fromisoformat("2026-10-20T12:00:00+00:00").timestamp() * 1000)
        lines = [f"LOG : Lua > [OptimizerTrial] drive telemetry flush begin format=2 world={world} samples=94 dropped=0 reason={reason}"]
        lines += [f"LOG : Lua > [OptimizerTrial] drive sample tsMs={epoch+second*1000} x=1 inVehicle=true speedKmh=40"
                  for second in range(-1, 93)]
        lines += [f"LOG : Lua > [OptimizerTrial] drive telemetry flush end format=2 world={world} samples=94 dropped=0 status=Complete"]
        text = "\n".join(lines) + "\n"
        (run / "session-console.txt").write_text(text)
        return run, text

    def test_buffered_context_survives_end_only_flush_with_original_sample_times(self):
        self.buffered_context_fixture("Control")
        self.buffered_context_fixture("Optimized")
        result = self.collect()
        self.assertEqual(result["Summary"]["status"], "Complete")
        for run in result["Summary"]["runs"]:
            context = run["gameContext"]
            self.assertEqual(context["status"], "Complete")
            self.assertEqual(context["samples"], 94)
            self.assertEqual(context["dropped"], 0)
            self.assertTrue(context["frameIntervalCovered"])
            self.assertEqual(context["maximumGapMs"], 1000)
            self.assertEqual(context["lastSampleTsMs"] - context["firstSampleTsMs"], 93000)
            with zipfile.ZipFile(result["Path"]) as archive:
                self.assertIn(b"drive telemetry flush end", archive.read("Runs/" + run["mode"] + "/session-console.txt"))

    def test_multiplayer_opaque_context_commits_before_lua_reset(self):
        for reason in ("Disconnect", "WorldExit", "PostSaveExit"):
            with self.subTest(reason=reason):
                for mode, token in (("Control", "a" * 32), ("Optimized", "b" * 32)):
                    self.buffered_context_fixture(mode, world="PZDrivingBench-OptimizerTrial-MP-" + token,
                                                  reason=reason)
                result = self.collect()
                self.assertEqual(result["Summary"]["status"], "Complete")
                self.assertTrue(all(run["gameContext"]["status"] == "Complete"
                                    for run in result["Summary"]["runs"]))

    def test_multiplayer_exit_reasons_do_not_relax_single_player_identity(self):
        self.buffered_context_fixture("Optimized")
        for world in ("PZDrivingBench-OptimizerTrial-Control", "PZDrivingBench-OptimizerTrial-MP-private-name",
                      "PZDrivingBench-OptimizerTrial-MP-" + "g" * 32):
            with self.subTest(world=world):
                self.buffered_context_fixture("Control", world=world, reason="Disconnect")
                context = self.collect()["Summary"]["runs"][0]["gameContext"]
                self.assertEqual(context["status"], "Incomplete")
                self.assertEqual(context["reason"], "InvalidMultiplayerGameContextIdentity")

    def test_buffered_context_missing_truncated_foreign_or_uncommitted_is_explicit(self):
        self.buffered_context_fixture("Optimized")
        for invalid, reason in (("forced-exit", "MissingWorldEndFlush"),
                                ("partial-write", "MissingWorldEndFlushCommit"),
                                ("dropped", "GameContextBufferTruncated"),
                                ("foreign-world", "GameContextWorldMismatch"),
                                ("sample-count", "GameContextFlushSampleCountMismatch"),
                                ("timestamp-order", "GameContextTimestampOrderInvalid"),
                                ("stale-interval", "GameContextDoesNotCoverFrameInterval"),
                                ("previous-world", "GameContextWorldMismatch"),
                                ("observer-error", "GameContextObserverFailed")):
            with self.subTest(invalid=invalid):
                run, text = self.buffered_context_fixture("Control")
                if invalid == "forced-exit":
                    text = "fixture without a final flush\n"
                elif invalid == "partial-write":
                    text = text[:text.index("LOG : Lua > [OptimizerTrial] drive telemetry flush end")]
                elif invalid == "dropped":
                    text = text.replace("dropped=0", "dropped=5").replace("status=Complete", "status=Incomplete")
                elif invalid == "foreign-world":
                    text = text.replace("OptimizerTrial-Control", "OptimizerTrial-Foreign")
                elif invalid == "sample-count":
                    text = text.replace("samples=94", "samples=95")
                elif invalid == "timestamp-order":
                    lines = text.splitlines()
                    lines[2] = lines[1]
                    text = "\n".join(lines) + "\n"
                elif invalid == "stale-interval":
                    diagnostic_path = run / "diagnostics.json"
                    diagnostic = json.loads(diagnostic_path.read_text())
                    diagnostic.update(frameRequestedUtc="2026-10-21T12:00:00Z", frameAcknowledgedUtc="2026-10-21T12:00:01Z")
                    diagnostic_path.write_text(json.dumps(diagnostic))
                elif invalid == "previous-world":
                    text += text.replace("OptimizerTrial-Control", "OptimizerTrial-LaterWorld")
                elif invalid == "observer-error":
                    text = text.replace("status=Complete", "status=Incomplete")
                (run / "session-console.txt").write_text(text)
                result = self.collect()
                context = result["Summary"]["runs"][0]["gameContext"]
                self.assertNotEqual(context["status"], "Complete")
                self.assertEqual(context["reason"], reason)
                self.assertTrue(any(reason in issue for issue in result["Summary"]["runs"][0]["issues"]))
                with zipfile.ZipFile(result["Path"]) as archive:
                    self.assertEqual(archive.read("Runs/Control/session-console.txt").decode(), text)

    def test_legacy_context_archives_do_not_require_a_new_flush_marker(self):
        result = self.collect()
        self.assertEqual(result["Summary"]["status"], "Complete")
        self.assertEqual([run["gameContext"]["status"] for run in result["Summary"]["runs"]], ["Legacy", "Legacy"])

    def extended_fixture(self, mode, *, status="Complete"):
        run = self.runs / (mode.lower() + "-run")
        launch = json.loads((run / "launch.json").read_text())
        diagnostic = json.loads((run / "diagnostics.json").read_text())
        diagnostic.update(diagnosticsVersion=3, extendedStatus="Complete", wprStatus=status)
        (run / "diagnostics.json").write_text(json.dumps(diagnostic))
        readiness = {"format": 1, "gameOptions": {"status": "Read", "targetStatus": "Matches", "values": {
            "width": "2560", "height": "1440", "vsync": "false", "frameRate": "144"}}}
        for name in ("capture-readiness-before.json", "capture-readiness.json"):
            (run / name).write_text(json.dumps(readiness))
        (run / "sensor-coverage.json").write_text(json.dumps({"format": 1, "status": "Unknown", "coverage": {}}))
        capture_id = ("1" if mode == "Control" else "2") * 32
        relative = "WPR/" + capture_id
        directory = run / relative
        directory.mkdir(parents=True, exist_ok=True)
        trace = directory / "drive.etl"
        trace.write_bytes(b"fixture ETL " + mode.encode())
        receipt = {"format": 1, "targetPid": launch["Pid"], "processStartUtc": launch["ProcessStartUtc"],
                   "captureId": capture_id, "instanceName": "PZTrial_" + capture_id, "status": status,
                   "loggingMode": "File", "traceFile": "drive.etl", "traceBytes": trace.stat().st_size,
                   "traceSha256": hashlib.sha256(trace.read_bytes()).hexdigest(), "headerValidated": True,
                   "startedUtc": "2026-10-20T12:00:00Z", "stopRequestedUtc": "2026-10-20T12:01:59Z",
                   "stoppedUtc": "2026-10-20T12:02:00Z"}
        wrapper = {"format": 1, "relativeDirectory": relative, "receipt": receipt}
        (directory / "wpr-status.json").write_text(json.dumps(receipt))
        (run / "wpr-capture.json").write_text(json.dumps(wrapper))
        return run, wrapper, directory

    def test_extended_complete_bundle_allows_only_final_wpr_artifacts_and_retry(self):
        control, _, directory = self.extended_fixture("Control")
        self.extended_fixture("Optimized")
        for name in ("control.json", "start.request.json", "stop.request.json", "wpr-status.json.pending"):
            (directory / name).write_text("private control fixture")
        (directory / "temp").mkdir()
        (directory / "temp" / "raw.etl").write_text("unfinalized private trace")
        original = {p: p.read_bytes() for p in self.runs.rglob("*") if p.is_file()}
        result = self.collect()
        self.assertEqual(result["Summary"]["status"], "Complete")
        self.assertEqual(result["Summary"]["settingsComparison"]["status"], "Matches")
        self.assertEqual(result["Summary"]["comparisonWarnings"], [])
        run = result["Summary"]["runs"][0]
        self.assertTrue(run["wpr"]["verified"])
        self.assertEqual(run["capFrameX"]["sensorCoverageFile"], "Runs/Control/sensor-coverage.json")
        with zipfile.ZipFile(result["Path"]) as archive:
            names = archive.namelist()
            for name in ("capture-readiness-before.json", "capture-readiness.json", "sensor-coverage.json", "wpr-capture.json"):
                self.assertIn("Runs/Control/" + name, names)
            wpr_names = {Path(n).name for n in names if "/WPR/" in n}
            self.assertEqual(wpr_names, {"wpr-status.json", "drive.etl"})
            self.assertEqual(archive.read(run["wpr"]["file"]), (directory / "drive.etl").read_bytes())
        again = self.collect()
        self.assertNotEqual(result["Path"], again["Path"])
        self.assertTrue(again["Summary"]["runs"][0]["wpr"]["verified"])
        self.assertEqual(original, {p: p.read_bytes() for p in self.runs.rglob("*") if p.is_file()})

    def test_extended_missing_artifacts_or_unavailable_wpr_is_incomplete(self):
        run, wrapper, directory = self.extended_fixture("Control", status="Unavailable")
        self.extended_fixture("Optimized")
        (run / "capture-readiness-before.json").unlink()
        (run / "sensor-coverage.json").unlink()
        (directory / "drive.etl").unlink()
        result = self.collect()
        summary = result["Summary"]["runs"][0]
        self.assertEqual(summary["status"], "Incomplete")
        self.assertIn("Missing capture-readiness-before.json", summary["issues"])
        self.assertIn("Missing sensor-coverage.json", summary["issues"])
        self.assertFalse(summary["wpr"]["verified"])

    def test_wpr_failed_save_retains_separate_cleanup_and_profile_evidence_without_etl(self):
        run, wrapper, directory = self.extended_fixture("Control", status="Incomplete")
        self.extended_fixture("Optimized")
        wrapper["receipt"].update(reason="OwnedSessionSaveFailed", saveFailure="OwnedSessionSaveFailed",
                                  cleanupState="Absent", profileState="Absent",
                                  profileSha256="a" * 64, observedTempBytes=2147483648)
        (run / "wpr-capture.json").write_text(json.dumps(wrapper))
        (directory / "wpr-status.json").write_text(json.dumps(wrapper["receipt"]))
        (directory / "drive.etl").unlink()
        (self.root / "PZTrial.wprp").write_text("fixture profile")
        temp = directory / "temp"
        temp.mkdir()
        (temp / "owned.etl").write_bytes(b"partial")
        (temp / "foreign.etl").symlink_to(self.control)
        result = self.collect()
        summary = result["Summary"]["runs"][0]
        self.assertEqual("Incomplete", summary["status"])
        self.assertFalse(summary["wpr"]["verified"])
        self.assertIsNone(summary["wpr"]["file"])
        self.assertEqual(["temp/owned.etl"], [row["relativePath"] for row in summary["wpr"]["temporaryFiles"]])
        self.assertFalse(summary["wpr"]["temporaryFiles"][0]["included"])
        for field in ("reason", "saveFailure", "cleanupState", "profileState", "profileSha256", "observedTempBytes"):
            self.assertEqual(wrapper["receipt"][field], summary["wpr"][field])
        with zipfile.ZipFile(result["Path"]) as archive:
            self.assertEqual(b"fixture profile", archive.read("PZTrial.wprp"))

    def test_completed_wpr_rejects_conflicting_profile_receipts(self):
        run, wrapper, directory = self.extended_fixture("Control")
        self.extended_fixture("Optimized")
        wrapper["receipt"]["profileSha256"] = "a" * 64
        (run / "wpr-capture.json").write_text(json.dumps(wrapper))
        saved = dict(wrapper["receipt"], profileSha256="b" * 64)
        (directory / "wpr-status.json").write_text(json.dumps(saved))
        result = self.collect()
        summary = result["Summary"]["runs"][0]
        self.assertEqual("Incomplete", summary["status"])
        self.assertFalse(summary["wpr"]["verified"])
        self.assertTrue(any("WPR wrapper/status mismatch: profileSha256" in issue for issue in summary["issues"]))

    def test_owned_partial_wpr_is_preserved_explicitly_unverified(self):
        run, wrapper, directory = self.extended_fixture("Control", status="Incomplete")
        self.extended_fixture("Optimized")
        wrapper["receipt"].update(traceSha256=None, traceBytes=None, stoppedUtc=None, headerValidated=False)
        (run / "wpr-capture.json").write_text(json.dumps(wrapper))
        (directory / "wpr-status.json").write_text(json.dumps(wrapper["receipt"]))
        result = self.collect()
        summary = result["Summary"]["runs"][0]
        self.assertEqual(summary["status"], "Incomplete")
        self.assertFalse(summary["wpr"]["verified"])
        self.assertEqual(len(summary["wpr"]["unverifiedFiles"]), 1)
        with zipfile.ZipFile(result["Path"]) as archive:
            self.assertEqual(archive.read(summary["wpr"]["file"]), (directory / "drive.etl").read_bytes())

    def test_wpr_foreign_paths_identity_hash_and_symlink_never_include_trace(self):
        self.extended_fixture("Optimized")
        for invalid in ("absolute", "traversal", "backslash", "foreign-id", "pid", "start", "instance", "hash", "bytes", "status-pid", "symlink"):
            with self.subTest(invalid=invalid):
                run, wrapper, directory = self.extended_fixture("Control")
                receipt = wrapper["receipt"]
                if invalid == "absolute":
                    wrapper["relativeDirectory"] = str(directory)
                elif invalid == "traversal":
                    wrapper["relativeDirectory"] = "WPR/../WPR/" + receipt["captureId"]
                elif invalid == "backslash":
                    wrapper["relativeDirectory"] = wrapper["relativeDirectory"].replace("/", "\\")
                elif invalid == "foreign-id":
                    wrapper["relativeDirectory"] = "WPR/" + "2" * 32
                elif invalid == "pid":
                    receipt["targetPid"] = 42
                elif invalid == "start":
                    receipt["processStartUtc"] = "2026-10-20T09:59:59Z"
                elif invalid == "instance":
                    receipt["instanceName"] = "Other"
                elif invalid == "hash":
                    receipt["traceSha256"] = "0" * 64
                    # Both receipts agree; the actual ETL must still be hashed.
                    (directory / "wpr-status.json").write_text(json.dumps(receipt))
                elif invalid == "bytes":
                    receipt["traceBytes"] += 1
                elif invalid == "status-pid":
                    status = dict(receipt, targetPid=42)
                    (directory / "wpr-status.json").write_text(json.dumps(status))
                elif invalid == "symlink":
                    trace = directory / "drive.etl"
                    trace.unlink()
                    trace.symlink_to(self.control)
                (run / "wpr-capture.json").write_text(json.dumps(wrapper))
                result = self.collect()
                summary = result["Summary"]["runs"][0]
                self.assertEqual(summary["status"], "Incomplete")
                self.assertIsNone(summary["wpr"]["file"])
                self.assertEqual(summary["wpr"]["unverifiedFiles"], [])
                with zipfile.ZipFile(result["Path"]) as archive:
                    self.assertFalse(any(n.startswith("Runs/Control/WPR/") and n.endswith("drive.etl") for n in archive.namelist()))
                if (directory / "drive.etl").is_symlink():
                    (directory / "drive.etl").unlink()

    def test_wpr_partial_is_bounded_and_copy_hash_is_rechecked(self):
        run, wrapper, directory = self.extended_fixture("Control", status="Incomplete")
        self.extended_fixture("Optimized")
        with (directory / "drive.etl").open("wb") as trace:
            trace.truncate(2147483649)
        result = self.collect()
        self.assertIsNone(result["Summary"]["runs"][0]["wpr"]["file"])
        self.assertTrue(any("2 GiB" in issue for issue in result["Summary"]["runs"][0]["issues"]))
        self.extended_fixture("Control")
        before = """
$originalCopy=${function:Copy-TrialResultFile}
function Copy-TrialResultFile([string]$Source, [string]$Destination) {
 & $originalCopy $Source $Destination
 if ($Destination -match '/Runs/Control/WPR/.*/drive[.]etl$') { [IO.File]::AppendAllText($Destination,'changed') }
}
"""
        result = self.collect(before)
        summary = result["Summary"]["runs"][0]
        self.assertEqual(summary["status"], "Incomplete")
        self.assertFalse(summary["wpr"]["verified"])
        self.assertIsNone(summary["wpr"]["file"])
        self.assertTrue(any("changed during collection" in issue for issue in summary["issues"]))

    def test_saved_settings_mismatch_and_unknown_are_comparison_warnings(self):
        self.extended_fixture("Control")
        run, _, _ = self.extended_fixture("Optimized")
        path = run / "capture-readiness.json"
        data = json.loads(path.read_text())
        data["gameOptions"]["values"]["frameRate"] = "60"
        path.write_text(json.dumps(data))
        result = self.collect()
        self.assertEqual(result["Summary"]["settingsComparison"]["status"], "Mismatch")
        self.assertTrue(any("Mismatch" in warning for warning in result["Summary"]["comparisonWarnings"]))
        data["gameOptions"]["status"] = "Unknown"
        path.write_text(json.dumps(data))
        result = self.collect()
        self.assertEqual(result["Summary"]["settingsComparison"]["status"], "Unknown")
        self.assertTrue(result["Summary"]["comparisonWarnings"])

    def test_wpr_time_coverage_requires_full_automatic_frame_interval(self):
        self.automatic_fixture("Control")
        self.automatic_fixture("Optimized")
        self.extended_fixture("Optimized")
        for invalid in (None, "started-late", "started-between-request-and-ack", "stopped-early",
                        "stop-requested-early-merge-completed-late", "stop-request-after-completion", "missing-start", "missing-stop-request"):
            with self.subTest(invalid=invalid):
                run, wrapper, directory = self.extended_fixture("Control")
                if invalid == "started-late":
                    wrapper["receipt"]["startedUtc"] = "2026-10-20T12:00:02Z"
                elif invalid == "started-between-request-and-ack":
                    wrapper["receipt"]["startedUtc"] = "2026-10-20T12:00:00.500Z"
                elif invalid == "stopped-early":
                    wrapper["receipt"]["stoppedUtc"] = "2026-10-20T12:01:30Z"
                elif invalid == "stop-requested-early-merge-completed-late":
                    wrapper["receipt"]["stopRequestedUtc"] = "2026-10-20T12:01:30Z"
                    wrapper["receipt"]["stoppedUtc"] = "2026-10-20T12:02:50Z"
                elif invalid == "stop-request-after-completion":
                    wrapper["receipt"]["stopRequestedUtc"] = "2026-10-20T12:02:01Z"
                elif invalid == "missing-start":
                    wrapper["receipt"]["startedUtc"] = None
                elif invalid == "missing-stop-request":
                    wrapper["receipt"]["stopRequestedUtc"] = None
                (run / "wpr-capture.json").write_text(json.dumps(wrapper))
                (directory / "wpr-status.json").write_text(json.dumps(wrapper["receipt"]))
                result = self.collect(automatic=True)
                summary = result["Summary"]["runs"][0]
                self.assertTrue(summary["wpr"]["verified"])
                self.assertIsNotNone(summary["wpr"]["file"])
                if invalid is None:
                    self.assertEqual(summary["status"], "Complete")
                    self.assertEqual(summary["wpr"]["captureCoverage"], "Complete")
                else:
                    self.assertEqual(summary["status"], "Incomplete")
                    self.assertEqual(summary["wpr"]["captureCoverage"], "Unknown")
                    self.assertTrue(any("coverage" in issue for issue in summary["issues"]))

    def test_automatic_receipts_bundle_exact_raw_files_without_arguments(self):
        control, control_wrapper = self.automatic_fixture("Control")
        optimized, optimized_wrapper = self.automatic_fixture("Optimized")
        (control / "CapFrameX" / "unrelated.json").write_text("private unrelated data")
        result = self.collect(automatic=True)
        self.assertEqual(result["Summary"]["status"], "Complete")
        with zipfile.ZipFile(result["Path"]) as archive:
            names = archive.namelist()
            for mode, wrapper in (("Control", control_wrapper), ("Optimized", optimized_wrapper)):
                self.assertIn("Runs/" + mode + "/frame-capture.json", names)
                for kind in ("Json", "Csv"):
                    source = Path(wrapper["result"][kind])
                    archived = "Runs/" + mode + "/CapFrameX/" + source.name
                    self.assertEqual(archive.read(archived), source.read_bytes())
            self.assertFalse(any("unrelated" in name for name in names))
            run = result["Summary"]["runs"][0]
            self.assertEqual(run["capFrameX"]["assignment"], "Automatic run receipt")
            self.assertTrue(run["capFrameX"]["csvFile"].endswith(".json.csv"))

    def test_automatic_partial_capture_preserves_valid_json_and_logs(self):
        control, wrapper = self.automatic_fixture("Control")
        self.automatic_fixture("Optimized")
        Path(wrapper["result"]["Csv"]).unlink()
        result = self.collect(automatic=True)
        self.assertEqual(result["Summary"]["status"], "Incomplete")
        run = result["Summary"]["runs"][0]
        self.assertIsNotNone(run["capFrameX"]["file"])
        self.assertIsNone(run["capFrameX"]["csvFile"])
        self.assertTrue(any("Csv" in issue for issue in run["issues"]))
        with zipfile.ZipFile(result["Path"]) as archive:
            self.assertIn("Runs/Control/frame-capture.json", archive.namelist())
            self.assertIn("Runs/Control/stdout.txt", archive.namelist())
            self.assertIn(run["capFrameX"]["file"], archive.namelist())

    def test_automatic_path_traversal_other_run_and_hash_mismatch_are_incomplete(self):
        for invalid in ("outside", "other-run", "traversal", "hash", "symlink"):
            with self.subTest(invalid=invalid):
                control, wrapper = self.automatic_fixture("Control")
                _, other = self.automatic_fixture("Optimized")
                original = Path(wrapper["result"]["Json"])
                if invalid == "outside":
                    wrapper["result"]["Json"] = str(self.control)
                elif invalid == "other-run":
                    wrapper["result"]["Json"] = other["result"]["Json"]
                    wrapper["result"]["JsonSha256"] = other["result"]["JsonSha256"]
                elif invalid == "traversal":
                    wrapper["result"]["Json"] = str(original.parent / ".." / "CapFrameX" / original.name)
                elif invalid == "hash":
                    wrapper["result"]["JsonSha256"] = "0" * 64
                else:
                    original.unlink()
                    original.symlink_to(self.control)
                (control / "frame-capture.json").write_text(json.dumps(wrapper))
                result = self.collect(automatic=True)
                run = result["Summary"]["runs"][0]
                self.assertEqual(run["status"], "Incomplete")
                self.assertIsNone(run["capFrameX"]["file"])
                self.assertTrue(any("Invalid automatic CapFrameX Json" in issue for issue in run["issues"]))
                with zipfile.ZipFile(result["Path"]) as archive:
                    self.assertNotIn("Runs/Control/CapFrameX/" + original.name, archive.namelist())
                if original.is_symlink():
                    original.unlink()

    def test_unknown_automatic_post_preserves_only_owned_unverified_exports(self):
        control, wrapper = self.automatic_fixture("Control")
        self.automatic_fixture("Optimized")
        wrapper.update(status="Incomplete", result=None, error="POST outcome unknown")
        wrapper["request"].pop("requestedUtc")
        wrapper["request"].pop("acknowledgedUtc")
        wrapper["request"]["preparedUtc"] = "2026-10-20T12:00:00Z"
        (control / "frame-capture.json").write_text(json.dumps(wrapper))
        directory = control / "CapFrameX"
        expected = {"CapFrameX-java.exe-2026-10-20.json": b'{"partial":',
                    "CapFrameX-java.exe-2026-10-20.json.csv": b"Application,ProcessID\njava.exe,"}
        for name, data in expected.items():
            (directory / name).write_bytes(data)
        for name in ("account.json", "CapFrameX-other.exe-2026-10-20.json", "CapFrameX-java.exe-private.txt"):
            (directory / name).write_text("unrelated data")
        (directory / "CapFrameX-java.exe-linked.json").symlink_to(self.control)
        nested = directory / "CapFrameX-java.exe-directory.json"
        nested.mkdir()
        (nested / "CapFrameX-java.exe-nested.json").write_text("unrelated nested data")
        result = self.collect(automatic=True)
        run = result["Summary"]["runs"][0]
        self.assertEqual(run["status"], "Incomplete")
        self.assertIsNone(run["capFrameX"]["file"])
        self.assertIsNone(run["capFrameX"]["csvFile"])
        self.assertTrue(any("unverified" in issue for issue in run["issues"]))
        self.assertEqual(len(run["capFrameX"]["unverifiedFiles"]), 2)
        with zipfile.ZipFile(result["Path"]) as archive:
            raw = [name for name in archive.namelist() if name.startswith("Runs/Control/CapFrameX-unverified/")]
            self.assertEqual({Path(name).name for name in raw}, set(expected))
            for name in raw:
                self.assertEqual(archive.read(name), expected[Path(name).name])
            self.assertIn("Runs/Control/frame-capture.json", archive.namelist())

    def test_unverified_exports_require_exact_owned_directory_and_are_bounded(self):
        control, wrapper = self.automatic_fixture("Control")
        _, other = self.automatic_fixture("Optimized")
        directory = control / "CapFrameX"
        wrapper.update(status="Incomplete", result=None)
        for invalid_directory in (str(self.root), other["request"]["directory"]):
            wrapper["request"]["directory"] = invalid_directory
            (control / "frame-capture.json").write_text(json.dumps(wrapper))
            (directory / "CapFrameX-java.exe-owned.json").write_text("partial")
            result = self.collect(automatic=True)
            self.assertEqual(result["Summary"]["runs"][0]["capFrameX"]["unverifiedFiles"], [])
        wrapper["request"]["directory"] = str(directory)
        (control / "frame-capture.json").write_text(json.dumps(wrapper))
        for index in range(17):
            (directory / ("CapFrameX-java.exe-%02d.json" % index)).write_text("partial")
        with (directory / "CapFrameX-java.exe-00-too-large.json").open("wb") as large:
            large.truncate(268435457)
        result = self.collect(automatic=True)
        run = result["Summary"]["runs"][0]
        self.assertEqual(len(run["capFrameX"]["unverifiedFiles"]), 16)
        self.assertTrue(any("256 MiB" in issue for issue in run["issues"]))
        self.assertTrue(any("16 files" in issue for issue in run["issues"]))
        with zipfile.ZipFile(result["Path"]) as archive:
            self.assertFalse(any("too-large" in name for name in archive.namelist()))

    def test_automatic_copy_is_hash_verified_and_changed_file_omitted(self):
        _, wrapper = self.automatic_fixture("Control")
        self.automatic_fixture("Optimized")
        before = """
$originalCopy=${function:Copy-TrialResultFile}
function Copy-TrialResultFile([string]$Source, [string]$Destination) {
 & $originalCopy $Source $Destination
 if ($Destination -match '/Runs/Control/CapFrameX/.*[.]json$') { [IO.File]::AppendAllText($Destination,'changed') }
}
"""
        result = self.collect(before, automatic=True)
        run = result["Summary"]["runs"][0]
        self.assertEqual(run["status"], "Incomplete")
        self.assertIsNone(run["capFrameX"]["file"])
        self.assertIsNotNone(run["capFrameX"]["csvFile"])
        self.assertTrue(any("changed during collection" in issue for issue in run["issues"]))
        with zipfile.ZipFile(result["Path"]) as archive:
            self.assertNotIn("Runs/Control/CapFrameX/" + Path(wrapper["result"]["Json"]).name, archive.namelist())

    def test_automatic_receipt_wrong_pid_mode_or_status_never_consumes_files(self):
        for field, value in (("targetPid", 42), ("mode", "Optimized"), ("status", "Incomplete")):
            with self.subTest(field=field):
                control, wrapper = self.automatic_fixture("Control")
                self.automatic_fixture("Optimized")
                wrapper[field] = value
                (control / "frame-capture.json").write_text(json.dumps(wrapper))
                result = self.collect(automatic=True)
                run = result["Summary"]["runs"][0]
                self.assertEqual(run["status"], "Incomplete")
                self.assertIsNone(run["capFrameX"]["file"])
                self.assertIsNone(run["capFrameX"]["csvFile"])
                with zipfile.ZipFile(result["Path"]) as archive:
                    self.assertIn("Runs/Control/frame-capture.json", archive.namelist())
                    self.assertFalse(any(name.startswith("Runs/Control/CapFrameX/") for name in archive.namelist()))

    def test_newest_automatic_run_missing_wrapper_never_uses_older_capture(self):
        self.automatic_fixture("Control")
        self.automatic_fixture("Optimized")
        latest = self.run_fixture("Control", "newest-control", "2026-10-21T12:00:00Z")
        launch = json.loads((latest / "launch.json").read_text())
        launch["automaticCapFrameX"] = True
        (latest / "launch.json").write_text(json.dumps(launch))
        result = self.collect(automatic=True)
        run = result["Summary"]["runs"][0]
        self.assertEqual(run["runId"], "newest-control")
        self.assertEqual(run["status"], "Incomplete")
        self.assertIn("Missing automatic frame-capture.json", run["issues"])
        self.assertIsNone(run["capFrameX"]["file"])

    def test_automatic_entrypoint_never_prompts_even_with_missing_wrapper(self):
        for complete in (True, False):
            with self.subTest(complete=complete):
                for mode in ("Control", "Optimized"):
                    run, _ = self.automatic_fixture(mode)
                    if not complete:
                        (run / "frame-capture.json").unlink()
                result = subprocess.run([PWSH, "-NoLogo", "-NoProfile", "-NonInteractive", "-File", str(SCRIPT),
                                         "-PackageRoot", str(self.root)], text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("result bundle:", result.stdout)
                self.assertIn("Complete" if complete else "Incomplete", result.stdout)

    def entrypoint_fixture(self):
        package = self.root / "trial package with spaces"
        package.mkdir()
        for source in tuple(self.root.iterdir()):
            if source != package:
                shutil.move(str(source), str(package / source.name))
        self.root = package
        self.runs = package / "Profiles" / "OptimizerTrial" / "TrialRuns"
        self.control = package / "control capture.json"
        self.optimized = package / "optimized capture.json"
        script = package / SCRIPT.name
        shutil.copy2(SCRIPT, script)
        for mode in ("Control", "Optimized"):
            self.automatic_fixture(mode)
        foreign_cwd = package.parent / "unrelated working directory"
        foreign_cwd.mkdir()
        return script, foreign_cwd

    def run_entrypoint(self, script, cwd, *arguments):
        return subprocess.run([PWSH, "-NoLogo", "-NoProfile", "-NonInteractive", "-File", str(script),
                               *arguments], cwd=cwd, text=True, capture_output=True, timeout=20)

    def test_file_entrypoint_defaults_blank_root_to_script_directory(self):
        script, foreign_cwd = self.entrypoint_fixture()
        original = {path: path.read_bytes() for path in self.runs.rglob("*") if path.is_file()}
        for arguments in ((), ("-PackageRoot", ""), ("-PackageRoot", "  \t "),
                          ("-PackageRoot", str(self.root) + os.sep + ".")):
            with self.subTest(arguments=arguments):
                before = set((self.root / "Diagnostics").glob("*.zip"))
                result = self.run_entrypoint(script, foreign_cwd, *arguments)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Complete result bundle:", result.stdout)
                created = set((self.root / "Diagnostics").glob("*.zip")) - before
                self.assertEqual(len(created), 1)
                with zipfile.ZipFile(created.pop()) as archive:
                    summary = json.loads(archive.read("comparison.json"))
                    self.assertEqual(summary["status"], "Complete")
                    for mode in ("Control", "Optimized"):
                        run = self.runs / (mode.lower() + "-run")
                        for name in ("launch.json", "frame-capture.json", "stdout.txt", "JFR/drive.jfr"):
                            self.assertEqual(archive.read("Runs/" + mode + "/" + name), (run / name).read_bytes())
                        for source in (run / "CapFrameX").iterdir():
                            self.assertEqual(archive.read("Runs/" + mode + "/CapFrameX/" + source.name), source.read_bytes())
                self.assertEqual(original, {path: path.read_bytes() for path in self.runs.rglob("*") if path.is_file()})
                self.assertFalse(list((self.root / "Diagnostics").glob(".collect-*")))
                self.assertFalse((foreign_cwd / "Diagnostics").exists())

    def test_file_entrypoint_invalid_explicit_root_reports_source_and_stack(self):
        script, foreign_cwd = self.entrypoint_fixture()
        missing_root = self.root / "missing package"
        result = self.run_entrypoint(script, foreign_cwd, "-PackageRoot", str(missing_root))
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(str(missing_root), result.stderr)
        self.assertIn("Get-ChildItem", result.stderr)
        self.assertRegex(result.stderr, r"at Get-LatestTrialResult, .*Collect-TrialResults[.]ps1: line [0-9]+")
        self.assertFalse(list(self.root.parent.rglob("*.zip")))
        self.assertFalse((foreign_cwd / "Diagnostics").exists())

    def test_file_entrypoint_missing_receipt_reports_source_and_stack_without_cwd_fallback(self):
        script, foreign_cwd = self.entrypoint_fixture()
        # A valid package in cwd must never substitute for the script's package.
        shutil.copytree(self.runs, foreign_cwd / "Profiles" / "OptimizerTrial" / "TrialRuns")
        (self.runs / "control-run" / "launch.json").unlink()
        original = {path: path.read_bytes() for path in self.runs.rglob("*") if path.is_file()}
        result = self.run_entrypoint(script, foreign_cwd)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("No Control launch receipt found", result.stderr)
        self.assertIn('throw "No $Mode launch receipt', result.stderr)
        self.assertRegex(result.stderr, r"at Get-LatestTrialResult, .*Collect-TrialResults[.]ps1: line [0-9]+")
        self.assertEqual(original, {path: path.read_bytes() for path in self.runs.rglob("*") if path.is_file()})
        self.assertFalse(list(self.root.parent.rglob("*.zip")))
        self.assertFalse((foreign_cwd / "Diagnostics").exists())

    def test_complete_archive_contains_both_runs_and_explicit_capture_mapping(self):
        run = self.runs / "control-run"
        (run / "previous-console.txt").write_text("old private log")
        (run / "JFR" / "account.txt").write_text("not diagnostics")
        (run / "JVM" / "account.txt").write_text("not diagnostics")
        (run / "Saves").mkdir()
        (run / "Saves" / "save.bin").write_text("not diagnostics")
        (self.root / "account.json").write_text("not diagnostics")
        result = self.collect()
        self.assertEqual(result["Summary"]["status"], "Complete")
        with zipfile.ZipFile(result["Path"]) as archive:
            names = archive.namelist()
            self.assertIn("Runs/Control/JFR/drive.jfr", names)
            self.assertIn("Runs/Optimized/session-console.txt", names)
            self.assertIn("Runs/Optimized/JVM/VM-flags.txt", names)
            self.assertIn("CapFrameX/control.json", names)
            self.assertFalse(any("previous-console" in name or "save.bin" in name or "account" in name for name in names))
            summary = json.loads(archive.read("comparison.json"))
            self.assertEqual(summary["runs"][0]["capFrameX"]["originalBasename"], self.control.name)
            self.assertEqual(len(summary["runs"][0]["capFrameX"]["sha256"]), 64)
        self.assertFalse(list((self.root / "Diagnostics").glob(".collect-*")))
        again = self.collect()
        self.assertNotEqual(result["Path"], again["Path"])
        self.assertTrue(Path(result["Path"]).is_file())

    def test_latest_failed_run_is_preserved_and_never_falls_back(self):
        latest = self.run_fixture("Control", "new-control", "2026-10-21T10:00:00Z", complete=False)
        (latest / "JFR" / "drive.jfr").unlink()
        receipt_path = latest / "launch.json"
        receipt = json.loads(receipt_path.read_text())
        receipt.update(JavaExitCode=1, Activation="Incomplete")
        receipt_path.write_text(json.dumps(receipt))
        result = self.collect()
        summary = result["Summary"]
        self.assertEqual(summary["status"], "Incomplete")
        self.assertEqual(summary["runs"][0]["runId"], "new-control")
        self.assertIn("Missing/empty JFR/drive.jfr", summary["runs"][0]["issues"])
        self.assertTrue((latest / "stdout.txt").is_file())

    def test_malformed_diagnostics_are_preserved_as_incomplete(self):
        diagnostics = self.runs / "control-run" / "diagnostics.json"
        diagnostics.write_text("{broken")
        result = self.collect()
        self.assertEqual(result["Summary"]["status"], "Incomplete")
        self.assertIn("Unreadable/invalid diagnostics receipt (preserved for analysis)", result["Summary"]["runs"][0]["issues"])
        with zipfile.ZipFile(result["Path"]) as archive:
            self.assertEqual(archive.read("Runs/Control/diagnostics.json"), b"{broken")

    def test_latest_open_launcher_blocks_archive(self):
        self.run_fixture("Control", "open-control", "2026-10-21T10:00:00Z", closed=False)
        result = self.collect(expect_success=False)
        self.assertIn("Latest Control run is still open", result.stderr)
        self.assertFalse((self.root / "Diagnostics").exists())

    def test_matching_live_process_blocks_even_closed_receipt(self):
        before = "$p = Join-Path $env:PZ_COLLECT_ROOT 'Profiles/OptimizerTrial/TrialRuns/control-run/launch.json'; $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; $j.Pid = $PID; $j.ProcessStartUtc = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'); $j | ConvertTo-Json | Set-Content -LiteralPath $p"
        result = self.collect(before, expect_success=False)
        self.assertIn("still running", result.stderr)

    def test_empty_and_duplicate_captures_are_rejected(self):
        self.control.write_text('{"CaptureData":{"MsBetweenPresents":[]}}')
        result = self.collect(expect_success=False)
        self.assertIn("no recognized nonempty", result.stderr)
        self.control.write_bytes(self.optimized.read_bytes())
        result = self.collect(expect_success=False)
        self.assertIn("two different", result.stderr)

    def test_reparse_capture_and_run_artifact_are_rejected(self):
        real = self.root / "real.json"
        self.control.rename(real)
        self.control.symlink_to(real)
        result = self.collect(expect_success=False)
        self.assertIn("Linked/reparse", result.stderr)
        self.control.unlink()
        self.control.write_bytes(real.read_bytes())
        stdout = self.runs / "control-run" / "stdout.txt"
        stdout.unlink()
        stdout.symlink_to(real)
        result = self.collect(expect_success=False)
        self.assertIn("Linked/reparse", result.stderr)
        self.assertFalse(list((self.root / "Diagnostics").glob("*.zip")))

    def test_missing_capframex_is_explicit_incomplete_and_keeps_logs(self):
        self.control = Path("-")
        result = self.collect()
        self.assertEqual(result["Summary"]["status"], "Incomplete")
        summary = result["Summary"]["runs"][0]
        self.assertIn("CapFrameX capture explicitly unavailable", summary["issues"])
        self.assertIsNone(summary["capFrameX"]["file"])
        with zipfile.ZipFile(result["Path"]) as archive:
            self.assertIn("Runs/Control/stdout.txt", archive.namelist())
            self.assertNotIn("CapFrameX/control.json", archive.namelist())

    def test_exit_without_launcher_finished_gate_blocks_collection(self):
        path = self.runs / "control-run" / "launch.json"
        receipt = json.loads(path.read_text())
        receipt["FinishedUtc"] = None
        path.write_text(json.dumps(receipt))
        result = self.collect(expect_success=False)
        self.assertIn("still open/incomplete", result.stderr)

    def test_dot_source_has_no_side_effects(self):
        result = subprocess.run([PWSH, "-NoProfile", "-Command", ". $env:PZ_COLLECT_SCRIPT; 'loaded'"],
            env=dict(os.environ, PZ_COLLECT_SCRIPT=str(SCRIPT)), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "loaded")


if __name__ == "__main__":
    unittest.main()
