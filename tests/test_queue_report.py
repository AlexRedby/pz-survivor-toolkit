"""Structured reports fail closed on incomplete or incomparable native evidence."""
import copy
import sys
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import report


class QueueReportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name).resolve()
        self.source = self.base / "source.lua"
        self.source.write_text("real source", encoding="utf-8")
        self.catalog = {"suites": {"health": {"status": "ready", "cases": [
            {"id": "bandageApply", "producer": "menu", "capability": "effect", "kinds": ["sp", "mp"], "modes": ["toolkit", "native"]}]},
            "crafting": {"status": "not-migrated", "cases": []}}}

    def digest(self, path):
        return report.hashlib.sha256(path.read_bytes()).hexdigest()

    def freeze(self, root):
        paths = [path for path in root.iterdir() if path.is_file() and path.name in
                 ("selection.json", "runtime.json", "settings-fingerprint.json", "source-manifest.json", "manifest.json", "initial-settings.json")]
        for role in ("server", "client1", "client2"):
            for sub in ("mods", "classes", "Lua"):
                paths += [path for path in (root / role / sub).rglob("*") if path.is_file()]
        report.write_json(root / "snapshot-hashes.json", {path.relative_to(root).as_posix(): self.digest(path) for path in paths})

    def fixture(self, name="run", kind="sp", mode="toolkit", status="passed"):
        root = self.base / name
        root.mkdir()
        selection = {"schema_version": 1, "suite": "health", "kind": kind, "mode": mode, "cases": ["bandageApply"],
                     "mods": ["PZSurvivorToolkit"], "languages": ["EN"] if kind == "sp" else ["EN", "RU"], "expected_checks": 3}
        report.write_json(root / "selection.json", selection)
        report.write_json(root / "source-manifest.json", {str(self.source): self.digest(self.source)})
        report.write_json(root / "runtime.json", {"kind": kind})
        report.write_json(root / "settings-fingerprint.json", {"sha256": "a" * 64})
        report.write_json(root / "manifest.json", {"mods": []})
        report.write_json(root / "initial-settings.json", {"voiceEnable": False})
        roles = ["client1"] if kind == "sp" else ["server", "client1", "client2"]
        clients = [role for role in roles if role != "server"]
        receipts = []
        for role in roles:
            for sub in ("mods", "classes", "Lua"):
                directory = root / role / sub
                directory.mkdir(parents=True)
                (directory / "input").write_text("frozen", encoding="utf-8")
            if role == "server":
                continue
            context = {"actor": role, "suite": "health", "kind": kind, "mode": mode}
            records = [dict(context, event="setup", cases=selection["cases"], expected=1,
                            queueEnabled=mode == "toolkit", nativeDurations=True, language="RU" if role == "client2" else "EN"),
                       dict(context, event="case", id="bandageApply", status=status),
                       dict(context, event="complete", cases=selection["cases"], expected=1,
                            performed=int(status != "skipped"), skipped=int(status == "skipped"), failed=int(status == "failed"))]
            if status == "skipped":
                records[1]["reason"] = "unsupported native prerequisite"
            markers = "".join("[QUEUE_TEST] " + marker + "\n" for marker in
                              ("VOICE_DISABLED", "DISPLAY_READY", "PREFLIGHT_COMPLETE mods=1 mode=" + mode, "TRUE_SP" if kind == "sp" else "NATIVE_CONNECTED"))
            text = markers + "".join(report.MARKER + json.dumps(event) + "\n" for event in records)
            if status == "passed":
                patient = "client2" if kind == "mp" and role == "client1" else role if kind == "sp" else "client1"
                receipt = "[QUEUE_TEST] HEALTH_AUTH_RECEIPT " + role + " phase=bandageApply ok=true patient=" + patient + " error=nil\n"
                receipts.append(receipt)
                if kind == "sp":
                    text += receipt
            (root / (role + "-launch.log")).write_text(text, encoding="utf-8")
        if kind == "mp":
            (root / "server-launch.log").write_text("[QUEUE_TEST] SERVER_READY\n" + "".join(receipts), encoding="utf-8")
        report.write_json(root / "execution.json", {"status": "completed", "processes": {role: {} for role in roles}})
        self.freeze(root)
        return root

    def mutate_event(self, root, event_name, **changes):
        path = root / "client1-launch.log"
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            if line.startswith(report.MARKER):
                event = json.loads(line[len(report.MARKER):])
                if event["event"] == event_name:
                    lines[index] = report.MARKER + json.dumps(dict(event, **changes))
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def test_complete_sp_and_concurrent_mp_reports_pass(self):
        for kind in ("sp", "mp"):
            with self.subTest(kind=kind):
                result = report.build_report(self.fixture(kind, kind), self.catalog)
                self.assertEqual(result["status"], "passed", result)
                self.assertEqual(len(result["coverage"]), 1 if kind == "sp" else 2)
                self.assertIn("Execution: completed", report.summary(result))

    def test_setup_identity_settings_and_case_list_are_required(self):
        changes = [{"actor": "client2"}, {"suite": "wrong"}, {"mode": "native"}, {"kind": "mp"},
                   {"cases": []}, {"queueEnabled": False}, {"nativeDurations": False}, {"language": "RU"}]
        for index, values in enumerate(changes):
            root = self.fixture(str(index))
            self.mutate_event(root, "setup", **values)
            with self.subTest(values=values):
                self.assertEqual(report.build_report(root, self.catalog)["functional"]["status"], "failed")
        root = self.fixture("no-setup")
        path = root / "client1-launch.log"
        path.write_text("\n".join(line for line in path.read_text().splitlines() if '"event": "setup"' not in line))
        self.assertEqual(report.build_report(root, self.catalog)["status"], "failed")

    def test_wrong_actual_patient_or_receipt_error_fails(self):
        root = self.fixture(kind="mp")
        path = root / "server-launch.log"
        text = path.read_text()
        for invalid in (text.replace("patient=client2", "patient=client1"), text.replace("error=nil", "error=unexpected")):
            path.write_text(invalid)
            self.assertEqual(report.build_report(root, self.catalog)["functional"]["status"], "failed")

    def test_native_only_skip_is_honest_but_not_a_supported_capability(self):
        self.catalog["suites"]["health"]["cases"][0]["modes"] = ["toolkit"]
        root = self.fixture(mode="native", status="skipped")
        result = report.build_report(root, self.catalog)
        self.assertEqual(result["functional"]["status"], "passed")
        row = next(row for row in report.matrix(self.catalog, [result])["rows"] if row.get("mode") == "native")
        self.assertEqual(row["status"], "unsupported")

    def test_case_and_complete_identity_counters_cases_and_order_are_checked(self):
        changes = [("case", {"actor": "wrong"}), ("case", {"suite": "wrong"}), ("complete", {"mode": "native"}),
                   ("complete", {"cases": []}), ("complete", {"performed": 2}), ("complete", {"performed": True})]
        for index, (name, values) in enumerate(changes):
            root = self.fixture(str(index))
            self.mutate_event(root, name, **values)
            with self.subTest(name=name, values=values):
                self.assertEqual(report.build_report(root, self.catalog)["status"], "failed")
        root = self.fixture("order")
        path = root / "client1-launch.log"
        lines = path.read_text().splitlines()
        complete = next(line for line in lines if '"event": "complete"' in line)
        lines.remove(complete)
        lines.insert(0, complete)
        path.write_text("\n".join(lines))
        self.assertEqual(report.build_report(root, self.catalog)["status"], "failed")

    def test_error_event_fails_and_performed_includes_failed_cases(self):
        root = self.fixture(status="failed")
        result = report.build_report(root, self.catalog)
        self.assertEqual(result["status"], "failed")
        self.assertFalse(any("completion counters" in issue for issue in result["functional"]["issues"]))
        root = self.fixture("error")
        self.mutate_event(root, "case", event="error", reason="deadline")
        self.assertEqual(report.build_report(root, self.catalog)["status"], "failed")

    def test_manifest_rejects_empty_missing_metadata_extra_and_escaped_files(self):
        root = self.fixture()
        self.assertEqual(report.verify_manifest(root, "snapshot-hashes.json"), [])
        manifest = report.read_json(root / "snapshot-hashes.json")
        (root / "client1/mods/extra.lua").write_text("new behavior")
        self.assertTrue(any("file set" in error for error in report.verify_manifest(root, "snapshot-hashes.json")))
        (root / "client1/mods/extra.lua").unlink()
        del manifest["selection.json"]
        manifest["../source.lua"] = self.digest(self.source)
        report.write_json(root / "snapshot-hashes.json", manifest)
        errors = report.verify_manifest(root, "snapshot-hashes.json")
        self.assertTrue(any("metadata missing" in error for error in errors))
        self.assertTrue(any("escapes run" in error for error in errors))
        report.write_json(root / "source-manifest.json", {})
        self.assertTrue(report.verify_manifest(root, "source-manifest.json", True))

    def test_execution_failed_or_missing_cannot_be_hidden_by_passing_logs(self):
        root = self.fixture()
        report.write_json(root / "execution.json", {"status": "failed", "error": "display guard stopped"})
        result = report.build_report(root, self.catalog)
        self.assertEqual(result["functional"]["status"], "passed")
        self.assertEqual(result["status"], "failed")
        self.assertIn("display guard stopped", report.summary(result))
        (root / "execution.json").unlink()
        self.assertEqual(report.build_report(root, self.catalog)["status"], "failed")

    def test_audit_keeps_preamble_errors_and_deduplicates_mirrors_with_counts(self):
        root = self.fixture()
        path = root / "client1-launch.log"
        path.write_text("java.lang.IllegalStateException: preamble\nLOG  : General > normal\n")
        self.assertEqual(len(report.audit_log(path, root / "client1")[0]), 1)
        error = "ERROR : General > failed native action\njava.lang.RuntimeException: cause\n at fixture.run(Fixture.java:12)\n"
        path.write_text(error * 2)
        (root / "client1/console.txt").write_text(error * 2)
        logs = root / "client1/Logs"
        logs.mkdir()
        (logs / "DebugLog.txt").write_text(error)
        result = report.audit_logs(root, ["client1"])["client1"]
        self.assertEqual(result["error_count"], 2)
        self.assertEqual(len(result["issues"]), 1)

    def test_missing_server_logs_fail_even_when_all_cases_were_skipped(self):
        root = self.fixture(kind="mp", status="skipped")
        (root / "server-launch.log").unlink()
        result = report.build_report(root, self.catalog)
        self.assertEqual(result["functional"]["status"], "passed")
        self.assertEqual(result["runtime"]["status"], "unavailable")
        self.assertEqual(result["status"], "failed")

    def test_matching_controls_compare_and_unsafe_or_incomplete_controls_do_not(self):
        current = report.build_report(self.fixture("toolkit"), self.catalog)
        control = report.build_report(self.fixture("native", mode="native"), self.catalog)
        self.assertTrue(report.compare(current, control)["compatible"])
        changes = [("settings_fingerprint", "b" * 64), ("execution", {"status": "failed"}),
                   ("provenance", {"verified": False}), ("functional", {"status": "failed"})]
        for key, value in changes:
            altered = dict(control, **{key: value})
            with self.subTest(key=key):
                self.assertFalse(report.compare(current, altered)["compatible"])
        altered = copy.deepcopy(control)
        altered["runtime"]["microphone"] = True
        self.assertFalse(report.compare(current, altered)["compatible"])
        altered = copy.deepcopy(control)
        altered["coverage"][0]["status"] = "skipped"
        self.assertFalse(report.compare(current, altered)["compatible"])

    def test_shared_unknown_errors_stay_in_review_and_new_errors_are_identified(self):
        toolkit = self.fixture("toolkit")
        native = self.fixture("native", mode="native")
        error = "ERROR: General > unknown fixture error\n"
        for root in (toolkit, native):
            with (root / "client1-launch.log").open("a") as stream:
                stream.write(error)
        control = report.build_report(native, self.catalog)
        self.assertEqual(control["status"], "needs-review")
        current = report.build_report(toolkit, self.catalog, control)
        self.assertEqual(current["runtime"]["status"], "unclassified-errors")
        self.assertEqual(current["status"], "needs-review")
        self.assertTrue(current["comparison"]["errors"]["client1"]["shared"])
        with (toolkit / "client1-launch.log").open("a") as stream:
            stream.write("ERROR: General > different unknown failure\n")
        current = report.build_report(toolkit, self.catalog, control)
        self.assertEqual(current["runtime"]["status"], "new-errors")
        self.assertEqual(current["status"], "needs-review")

    def test_fatal_errors_fail_with_or_without_a_matching_control(self):
        errors = ["java.lang.RuntimeException: same failure", "se.krka.kahlua.vm.KahluaException: same failure",
                  "java.lang.OutOfMemoryError: Java heap space", "java.sql.SQLException: database disk image is malformed",
                  "Failed to bind server port", "Unable to save world", "Cannot write players.db", "checksum mismatch", "# SIGSEGV"]
        for index, message in enumerate(errors):
            with self.subTest(message=message):
                toolkit = self.fixture("toolkit" + str(index))
                native = self.fixture("native" + str(index), mode="native")
                for root in (toolkit, native):
                    with (root / "client1-launch.log").open("a") as stream:
                        stream.write("ERROR: General > " + message + "\n")
                control = report.build_report(native, self.catalog)
                self.assertEqual(control["status"], "failed")
                current = report.build_report(toolkit, self.catalog, control)
                self.assertEqual(current["status"], "failed")
                self.assertEqual(current["runtime"]["status"], "failed")
                self.assertEqual(current["runtime"]["fatal_count"], 1)
                self.assertTrue(current["comparison"]["errors"]["client1"]["shared"])
        path = self.base / 'crash.log'
        path.write_text('# SIGSEGV (0xb) at pc=0x123\n')
        self.assertEqual(report.audit_log(path, self.base)[0][0]['severity'], 'fatal')

    def test_background_requires_exact_verified_profile_and_pinned_engine(self):
        root = self.fixture()
        game = self.base / "game"
        game.mkdir()
        jar = game / "projectzomboid.jar"
        jar.write_bytes(b"known engine")
        report.write_json(root / "runtime.json", {"game": str(game)})
        report.write_json(root / "source-manifest.json", {str(jar): self.digest(jar)})
        selection = {"suite": "animal-trailer", "kind": "mp", "clients": 1, "languages": ["EN"],
                     "cases": ["equipment-missing"], "mods": ["ZombieBuddy", "PZSurvivorToolkit"]}
        with patch.object(report, "BACKGROUND_GAME_SHA256", self.digest(jar)):
            self.assertTrue(report.background_profile(root, selection, True))
            self.assertFalse(report.background_profile(root, selection, False))
            for change in ({"suite": "health"}, {"cases": ["ghost"]}, {"kind": "sp"}, {"clients": 2},
                           {"languages": ["RU"]}, {"mods": [*selection["mods"], "UnknownMod"]}):
                self.assertFalse(report.background_profile(root, dict(selection, **change), True), change)
            report.write_json(root / "source-manifest.json", {str(jar): "0" * 64})
            self.assertFalse(report.background_profile(root, selection, True))
        (root / "runtime.json").unlink()
        self.assertFalse(report.background_profile(root, selection, True))

    def test_background_stays_visible_and_must_be_before_readiness_with_bounded_counts(self):
        root = self.fixture()
        message = "ERROR: General at FluidContainerScript.load > Sanitizing container name 'Large Bucket', name may not contain whitespaces.\n"
        ready = "LOG: Lua > [ANIMAL_TRAILER] CLIENT INGAME\n"
        path = root / "client1-launch.log"
        functional = path.read_text()
        path.write_text(message + ready + functional)
        with patch.object(report, "background_profile", return_value=True):
            value = report.build_report(root, self.catalog)
            self.assertEqual(value["status"], "passed")
            self.assertEqual(value["runtime"]["status"], "background-only")
            self.assertEqual(value["runtime"]["background_count"], 1)
            self.assertEqual(value["runtime"]["roles"]["client1"]["error_count"], 1)
            self.assertIn("1 background", report.summary(value))
            for text in (message * 3 + ready + functional, ready + message + functional, message + functional,
                         message.replace("Large Bucket", "Modded Bucket") + ready + functional,
                         message.replace("FluidContainerScript.load", "UnknownMod.load") + ready + functional):
                path.write_text(text)
                self.assertEqual(report.build_report(root, self.catalog)["status"], "needs-review")
            path.write_text(message + "java.lang.NullPointerException: hidden\n" + ready + functional)
            self.assertEqual(report.build_report(root, self.catalog)["status"], "failed")

    def test_known_property_fallback_requires_complete_original_stack_and_cannot_mask_fatal_mirror(self):
        root = self.fixture(kind="mp")
        path = root / "server-launch.log"
        error = ("ERROR: WorldGen > IsoPropertyType.lookupOrDefaultStr> Exception thrown\n"
                 "zombie.core.properties.IsoPropertyType$IsoPropertyTypeNotFoundException: Property Name not found: ladderW at IsoPropertyType.lookup(IsoPropertyType.java:273). Message: Property Name not found: ladderW\n"
                 "Stack trace:\n"
                 "zombie.core.properties.IsoPropertyType.lookup(IsoPropertyType.java:273)\n"
                 "zombie.core.properties.IsoPropertyType.lookupOrDefaultStr(IsoPropertyType.java:281)\n"
                 "zombie.core.TilePropertyAliasMap.register(TilePropertyAliasMap.java:54)\n"
                 "zombie.core.TilePropertyAliasMap.Generate(TilePropertyAliasMap.java:27)\n"
                 "zombie.iso.IsoWorld.GenerateTilePropertyLookupTables(IsoWorld.java:1337)\n"
                 "zombie.iso.IsoWorld.init(IsoWorld.java:2257)\n"
                 "zombie.network.GameServer.main(GameServer.java:817)\n")
        ready = "LOG: Lua > [ANIMAL_TRAILER] SERVER READY\n"
        original = path.read_text()
        path.write_text(error + ready + original)
        self.assertEqual(report.audit_logs(root, ["server"], True)["server"]["background_count"], 1)
        for changed in (error.replace("ladderW", "newProperty"), error.replace("GameServer.java:817", "GameServer.java:999"),
                        error + "java.lang.OutOfMemoryError: hidden\n"):
            path.write_text(changed + ready + original)
            self.assertEqual(report.audit_logs(root, ["server"], True)["server"]["fatal_count"], 1)
        logs = root / "server/Logs"
        logs.mkdir()
        (logs / "DebugLog.txt").write_text(error + ready)
        path.write_text(ready + error)
        merged = report.audit_logs(root, ["server"], True)["server"]
        self.assertEqual(merged["error_count"], 1)
        self.assertEqual(merged["fatal_count"], 1)

    def test_map_defects_and_fonts_remain_unclassified_even_with_background_enabled(self):
        root = self.fixture()
        path = root / "client1-launch.log"
        original = path.read_text()
        for message in ("duplicate RoomDef.metaID for room at 10707,9484,0",
                        "ERROR: Mannequin zone missing properties in media/maps/Muldraugh, KY/objects.lua coords: 13583, 1299, 0",
                        "AngelCodeFont failed to load page 0 texture media/mainfont_0.png"):
            path.write_text("ERROR: General > " + message + "\nLOG: Lua > [ANIMAL_TRAILER] CLIENT INGAME\n" + original)
            with patch.object(report, "background_profile", return_value=True):
                value = report.build_report(root, self.catalog)
            self.assertEqual(value["status"], "needs-review")
            self.assertEqual(value["runtime"]["unclassified_count"], 1)

    def test_error_like_setting_names_are_not_exceptions_and_indented_errors_are_audited(self):
        root = self.fixture()
        path = root / "client1-launch.log"
        path.write_text("LOG: General > WARN:MISSING in SettingsTable: AntiCheatPacketException\n"
                        "WARN: General > Failed sysctl call: Error code: 12.\n")
        self.assertEqual(report.audit_log(path, root / "client1")[0], [])
        for head in ("LOG: General > normal\n",
                     "ERROR: General at FluidContainerScript.load > Sanitizing container name 'Large Bucket', name may not contain whitespaces.\n"):
            for prefix in ("\t", "\t[16-10-26 06:21:54.733] "):
                path.write_text(head + prefix + "ERROR: Native > unexpected world metadata failure\nLOG: Lua > [ANIMAL_TRAILER] CLIENT INGAME\n")
                rows = report.audit_log(path, root / "client1", background=True)[0]
                self.assertTrue(any(row['message'] == 'unexpected world metadata failure' and row['severity'] == 'unclassified' for row in rows))
        path.write_text("ERROR: General at FluidContainerScript.load > Sanitizing container name 'Large Bucket', name may not contain whitespaces.\n"
                        "unrecognized continuation\nLOG: Lua > [ANIMAL_TRAILER] CLIENT INGAME\n")
        self.assertEqual(report.audit_log(path, root / "client1", background=True)[0][0]['severity'], 'unclassified')

    def test_matrix_requires_verified_complete_actor_coverage_and_preserves_skips(self):
        complete = report.build_report(self.fixture(kind="mp"), self.catalog)
        def cell(value):
            return next(row for row in report.matrix(self.catalog, [value])["rows"]
                        if row.get("kind") == "mp" and row["mode"] == "toolkit")
        self.assertEqual(cell(complete)["status"], "passed")
        for key, value in (("functional", {"status": "failed"}), ("provenance", {"verified": False}), ("status", "failed")):
            self.assertEqual(cell(dict(complete, **{key: value}))["status"], "failed")
        partial = copy.deepcopy(complete)
        partial["coverage"].pop()
        self.assertEqual(cell(partial)["status"], "partial")
        partial["coverage"] = copy.deepcopy(complete["coverage"])
        partial["coverage"][1]["status"] = "skipped"
        self.assertEqual(cell(partial)["status"], "partial")
        for row in partial["coverage"]:
            row["status"] = "skipped"
        self.assertEqual(cell(partial)["status"], "skipped")


    def test_generated_user_data_is_allowed_but_prepared_inputs_stay_pinned(self):
        root = self.fixture()
        (root / "client1/Lua/ModOptions.ini").write_text("generated native options")
        (root / "client1/Lua/layout.ini").write_text("generated native layout")
        self.assertEqual(report.verify_manifest(root, "snapshot-hashes.json"), [])
        (root / "client1/Lua/input").write_text("changed prepared input")
        self.assertTrue(any("Changed input" in error for error in report.verify_manifest(root, "snapshot-hashes.json")))

    def test_timestamped_debug_log_matches_launch_without_warning_false_positives(self):
        root = self.fixture()
        plain = 'ERROR: General > engine failure\n\tjava.lang.RuntimeException: actual cause\n'
        (root / 'client1-launch.log').write_text(plain * 2)
        logs = root / 'client1/Logs'
        logs.mkdir()
        stamped = 'SLF4J(W): No SLF4J providers were found.\n16-10-2026 06:21:59.\n'
        stamped += '[16-10-26 06:21:59.959] WARN : General > Failed sysctl call: MemorySegment{address: 0x123}, Error code: 12.\n'
        stamped += ('[16-10-26 06:21:54.733] ' + plain.replace('engine failure', 'engine failure.')) * 2
        (logs / '2026_DebugLog.txt').write_text(stamped)
        result = report.audit_logs(root, ['client1'])['client1']
        self.assertEqual(result['error_count'], 2)
        self.assertEqual(len(result['issues']), 1)


if __name__ == "__main__":
    unittest.main()
