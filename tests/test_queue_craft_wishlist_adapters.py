"""Parser/staging tests use synthetic logs; they never claim native game coverage."""
import json
from pathlib import Path
import shutil
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from queue_checks.adapters import craft_wishlist as adapter


def selection(suite, case):
    mods = adapter.definitions()[suite]["default_mods"]
    return {"suite": suite, "cases": [case], "kind": "mp", "mode": "toolkit", "mods": mods,
            "ports": [18061, 18062], "languages": ["EN", "RU"]}


def client_log(value, role):
    suite, case = value["suite"], value["cases"][0]
    prefix = "[" + adapter.marker(value) + "] "
    names = json.loads((ROOT / "tests/native_queue/contributions" / suite / "stage-names.json").read_text())[case]
    lines = [prefix + "CONNECTED " + role + " language=" + ("EN" if role == "client1" else "RU")]
    if suite == "crafting-plans":
        lines.append(prefix + "EXPECTED checks=" + str(len(names)) + " scenario=" + case)
    if case == "ui":
        lines += [prefix + marker + " " + role for marker in ("PREVIEW_RENDERED", "FALLBACK_RENDERED", "WINDOW_GUARDS", "START_CALLBACK")]
        lines += [prefix + "SCROLLBAR_BOUNDS " + role + " label=" + label for label in ("constrained", "scrolled", "short", "wide")]
    lines += [prefix + "PASS " + name + " nil" for name in names]
    lines.append(prefix + "COMPLETE checks=" + str(len(names)) + " failures=0")
    return "\n".join(lines) + "\n"


def server_log(value):
    suite, case = value["suite"], value["cases"][0]
    lines = [adapter.server_ready(value)]
    if suite == "crafting-plans" and case == "crafting":
        lines += ["[CRAFT_TEST] SERVER_" + phase + "_VERIFY " + role + " ok=true error=nil"
                  for phase in ("CANCEL", "CHAIN") for role in ("client1", "client2")]
        lines.append("[CRAFT_TEST] SERVER_RACE_VERIFY ok=true completed=1 error=nil")
    elif suite == "crafting-plans" and case == "alternatives":
        lines += ["[CRAFT_TEST] SERVER_ALTERNATIVES_VERIFY " + role + " phase=" + phase + " ok=true error=nil"
                  for role in ("client1", "client2") for phase in ("chain", "repeat", "logs")]
    elif suite == "shared-wishlist" and case in ("full", "standalone"):
        lines += ["[WISHLIST_TEST] SERVER_VERIFY " + role + " ok=true" for role in ("client1", "client2")]
    if suite == "shared-wishlist" and case == "reload":
        lines[0:0] = ["[WISHLIST_TEST] RESTORE slot=a chars=12", "[WISHLIST_TEST] RESTORE_COMPLETE slots=1"]
    return "\n".join(lines) + "\n"


class CraftWishlistAdapterTests(unittest.TestCase):
    def test_every_preserved_scenario_and_exact_stage_guards(self):
        catalog = {"suites": adapter.definitions()}
        for suite, counts in adapter.COUNTS.items():
            for case, expected in counts.items():
                value = selection(suite, case)
                with self.subTest(suite=suite, case=case), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    for role in ("client1", "client2"):
                        text = client_log(value, role)
                        (root / (role + "-launch.log")).write_text(text)
                        self.assertTrue(adapter.complete(value, role, text))
                        self.assertEqual([], adapter._client_issues(text, value, role, case))
                        for broken in (text.replace("PASS ", "PASS unknown ", 1),
                                       text + "[" + adapter.marker(value) + "] COMPLETE checks=" + str(expected) + " failures=0\n",
                                       text.replace("language=EN" if role == "client1" else "language=RU", "language=wrong")):
                            self.assertTrue(adapter._client_issues(broken, value, role, case))
                        lines = text.splitlines()
                        first = next(i for i, line in enumerate(lines) if "] PASS " in line)
                        lines[first], lines[first + 1] = lines[first + 1], lines[first]
                        self.assertTrue(adapter._client_issues("\n".join(lines), value, role, case))
                    (root / "server-launch.log").write_text(server_log(value))
                    if case == "reload":
                        (root / "report.json").write_text(json.dumps({"status": "passed", "runtime": {"status": "clean"}}))
                        with patch.object(adapter, "_seed", return_value=(root, [])):
                            result = adapter.verify(root, value, catalog)
                    else:
                        result = adapter.verify(root, value, catalog)
                    self.assertEqual([], result["issues"])
                    self.assertEqual([expected, expected], [row["outcome"]["preserved_stages"] for row in result["outcomes"]])

    def test_identical_reload_headers_are_allowed_but_conflicting_headers_fail(self):
        value = selection("crafting-plans", "crafting")
        text = client_log(value, "client1")
        header = "[CRAFT_TEST] EXPECTED checks=20 scenario=crafting\n"
        self.assertEqual([], adapter._client_issues(header + text, value, "client1", "crafting"))
        self.assertTrue(adapter._client_issues(header.replace("checks=20", "checks=19") + text, value, "client1", "crafting"))
        self.assertTrue(adapter._client_issues(text.replace(header, ""), value, "client1", "crafting"))

    def test_failed_or_partial_completion_ends_lifecycle_but_fails_verification(self):
        for suite, case in (("crafting-plans", "crafting"), ("shared-wishlist", "full")):
            value = selection(suite, case)
            for count in (0, adapter.COUNTS[suite][case]):
                text = "[" + adapter.marker(value) + "] COMPLETE checks=" + str(count) + " failures=1\n"
                self.assertTrue(adapter.complete(value, "client1", text))
                self.assertTrue(adapter._client_issues(text, value, "client1", case))

    def test_authority_receipts_cannot_be_missing_or_duplicate(self):
        for suite, case in (("crafting-plans", "crafting"), ("crafting-plans", "alternatives"), ("shared-wishlist", "full")):
            value = selection(suite, case)
            text = server_log(value)
            self.assertEqual([], adapter._server_issues(text, value, case))
            receipt = text.splitlines()[1]
            for broken in (text.replace(receipt, ""), text + receipt + "\n", text.replace("ok=true", "ok=false", 1)):
                self.assertTrue(adapter._server_issues(broken, value, case))

    def test_native_ui_requires_all_render_and_scroll_markers(self):
        value = selection("crafting-plans", "ui")
        text = client_log(value, "client1")
        for marker in ("PREVIEW_RENDERED", "FALLBACK_RENDERED", "WINDOW_GUARDS", "START_CALLBACK", "label=wide"):
            self.assertTrue(adapter._client_issues(text.replace(marker, "MISSING"), value, "client1", "ui"))

    def test_staging_reuses_preserved_fixture_and_refuses_collisions(self):
        for suite, case in (("crafting-plans", "alternatives"), ("shared-wishlist", "standalone")):
            value = selection(suite, case)
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(root / role)} for role in ("server", "client1", "client2")}}
                adapter.stage(ROOT, root, None, None, value, {}, runtime)
                expected = adapter.HELPERS[suite]
                self.assertEqual([expected], runtime["fixture"]["mods"])
                snapshots = []
                for role in runtime["roles"]:
                    helper = root / role / "mods" / expected
                    snapshots.append({str(path.relative_to(helper)): path.read_bytes() for path in helper.rglob("*") if path.is_file()})
                    config = root / role / "Lua" / ("craft-fixture.txt" if suite == "crafting-plans" else "wishlist-fixture.txt")
                    self.assertEqual([role, case], config.read_text().splitlines()[:2])
                    self.assertEqual(0, config.stat().st_mode & 0o077)
                self.assertEqual(snapshots[0], snapshots[1])
                self.assertEqual(snapshots[1], snapshots[2])
                with self.assertRaises(ValueError):
                    adapter.stage(ROOT, root, None, None, value, {}, runtime)

    def test_selection_rejects_invalid_controls_and_missing_dependencies(self):
        value = selection("crafting-plans", "crafting")
        for changes in ({"mode": "native"}, {"kind": "sp"}, {"clients": 1}, {"cases": ["crafting", "ui"]},
                        {"ports": [18061, 18063]}, {"mods": ["PZSurvivorToolkit"]}):
            with self.assertRaises(ValueError):
                adapter.validate(dict(value, **changes))
        with self.assertRaisesRegex(ValueError, "seed_run"):
            adapter.validate(selection("shared-wishlist", "reload"))
        with self.assertRaisesRegex(ValueError, "integration missing"):
            adapter.validate(dict(selection("shared-wishlist", "full"), mods=["PZSurvivorToolkit", "PZSurvivorWishlist"]))
        for case in ("standalone", "visual", "reload"):
            spec = next(row for row in adapter.definitions()["shared-wishlist"]["cases"] if row["id"] == case)
            self.assertEqual(["toolkit"], spec["modes"])
            self.assertIn("no Toolkit queue", spec["control_reason"])
            with self.assertRaisesRegex(ValueError, "no Toolkit queue"):
                adapter.validate(dict(selection("shared-wishlist", case), mode="native"))

    def test_staging_does_not_write_bytecode_into_preserved_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project, output = root / "project", root / "run"
            relative = Path("tests/native_queue/contributions/shared-wishlist")
            source = project / relative
            source.mkdir(parents=True)
            shutil.copy2(ROOT / relative / "prepare.py", source)
            for side in ("client", "server"):
                shutil.copytree(ROOT / relative / side, source / side)
            runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(output / role)} for role in ("server", "client1", "client2")}}
            with patch.object(sys, "dont_write_bytecode", False):
                adapter.stage(project, output, None, None, selection("shared-wishlist", "standalone"), {}, runtime)
            self.assertFalse((source / "__pycache__").exists())

    def test_reload_requires_exact_restore_receipts_before_ready(self):
        value = selection("shared-wishlist", "reload")
        text = server_log(value)
        self.assertEqual([], adapter._server_issues(text, value, "reload"))
        for broken in (text.replace("RESTORE_COMPLETE slots=1", "RESTORE_COMPLETE slots=2"),
                       text.replace("RESTORE slot=a chars=12", "RESTORE slot=a chars=0"),
                       text + "[WISHLIST_TEST] RESTORE slot=a chars=12\n",
                       text.replace("[WISHLIST_TEST] RESTORE_COMPLETE slots=1\n", ""),
                       adapter.server_ready(value) + "\n" + text.replace(adapter.server_ready(value), "")):
            self.assertTrue(adapter._server_issues(broken, value, "reload"))

    def test_native_restore_roundtrip_and_fail_closed_guards(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        self.assertIsNotNone(lua, "Lua interpreter required for the retained native restore helper")
        code = r'''local restore = dofile(arg[1])
local files, current, server, client = {}, '/fixture/world', true, false
isServer=function() return server end
isClient=function() return client end
getCurrentSaveName=function() return current end
getFileWriter=function(path)
  return {write=function(_, text) files[path]=text end, close=function() end}
end
getFileReader=function(path)
  if not files[path] then return end
  local pos=1
  return {close=function() end, readLine=function()
    local a,b=files[path]:find('\n',pos,true)
    if not a then return end
    local line=files[path]:sub(pos,a-1); pos=b+1; return line
  end}
end
local text='PZSW\t1\t19\nEND\tfixture\n'
restore(current,{a=text,b=text})
local n=0; for path,value in pairs(files) do n=n+1; assert(value==text) end; assert(n==2)
assert(not pcall(restore,current,{a=text}))
files={}; assert(not pcall(restore,'other',{a=text}))
assert(not pcall(restore,current,{}))
assert(not pcall(restore,current,{foreign=text}))
server=false; assert(not pcall(restore,current,{a=text})); server=true
client=true; assert(not pcall(restore,current,{a=text})); client=false
getFileWriter=function() return nil end
assert(not pcall(restore,current,{a=text}))
print('PASS native restore roundtrip and guards')
'''
        result = subprocess.run([lua, "-", str(ROOT / "tests/native_queue/support/QueueWishlistRestore.lua")],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_store_prefix_matches_kahlua_utf16_units_and_path_chunks(self):
        cache = Path("/fixture/мир-😀/server")
        prefix = adapter._store_prefix(cache, "queue-smoke")
        chunks = prefix.relative_to(cache / "Lua/PZSurvivorWishlist").parts
        self.assertTrue(all(len(part) == 80 for part in chunks[:-1]))
        raw = bytes.fromhex("".join(chunks))
        self.assertEqual(str(cache / "Saves/Multiplayer/queue-smoke"), raw.decode("utf-16-be"))
        for name in ("..", "bad/name", None):
            with self.assertRaises(ValueError):
                adapter._store_prefix(cache, name)

    def test_generated_restore_preserves_unicode_world_and_slot_as_utf8_bytes(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        self.assertIsNotNone(lua, "Lua interpreter required for generated restore string roundtrip")
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            seed, output = base / "seed", base / "мир-😀"
            prefix = adapter._store_prefix(seed / "server", "queue-smoke")
            prefix.mkdir(parents=True)
            slot = prefix / "a.txt"
            text = 'PZSW\t1\t19\nL\tигрок-😀\t14\t\nE\tBase.Hammer\t7\t0\nEND\t19\t123\n'
            slot.write_text(text, encoding="utf-8")
            (seed / "runtime.json").write_text(json.dumps({"server_name": "queue-smoke"}))
            value = dict(selection("shared-wishlist", "reload"), options={"seed_run": str(seed)})
            runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(output / role)} for role in ("server", "client1", "client2")}}
            with patch.object(adapter, "_seed", return_value=(seed, [slot])):
                adapter.stage(ROOT, output, None, None, value, {}, runtime)
            modules = [output / role / "mods/WishlistTest/42/media/lua/server/WishlistSeedRestore.lua" for role in runtime["roles"]]
            contents = [path.read_bytes() for path in modules]
            self.assertEqual(contents, [contents[0]] * 3)
            self.assertTrue(contents[0].isascii(), "Kahlua's source lexer must only receive ASCII string literals")
            code = r'''local world, slots
require=function() return function(a,b) world,slots=a,b end end
dofile(arg[1]); WishlistSeedRestore()
io.write(world, '\0', slots.a)
'''
            result = subprocess.run([lua, "-", str(modules[0])], input=code.encode("ascii"), capture_output=True)
            self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", errors="replace"))
            world = str(output / "server/Saves/Multiplayer/queue-smoke")
            self.assertEqual(world.encode("utf-8") + b"\0" + text.encode("utf-8"), result.stdout)
            self.assertEqual(text.encode("utf-8"), slot.read_bytes(), "Seed bytes must remain unchanged")

    def test_reload_copies_only_owned_persisted_state_and_checks_seed(self):
        initial = selection("shared-wishlist", "standalone")
        with tempfile.TemporaryDirectory() as directory:
            seed, target = Path(directory).resolve() / "seed", Path(directory).resolve() / "target"
            seed.mkdir()
            runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(seed / role)} for role in ("server", "client1", "client2")}}
            evidence = {"selection.json": initial, "runtime.json": runtime,
                        "execution.json": {"status": "completed", "processes": {role: {"exit_code": 0} for role in runtime["roles"]}},
                        "report.json": {"status": "passed", "functional": {"status": "passed"}, "provenance": {"verified": True},
                                        "runtime": {"status": "clean", "microphone": False,
                                                    "roles": {role: {"available": True} for role in runtime["roles"]}}}}
            for name, data in evidence.items():
                (seed / name).write_text(json.dumps(data))
            for role in runtime["roles"]:
                (seed / (role + "-launch.log")).write_text(server_log(initial) if role == "server" else client_log(initial, role))
            state = seed / "server/Saves/Multiplayer/queue-smoke/global_mod_data.bin"
            state.parent.mkdir(parents=True)
            state.write_bytes(b"persisted-list-fixture")
            forbidden = seed / "server/Lua/unrelated.txt"
            forbidden.parent.mkdir(parents=True)
            forbidden.write_text("do not copy")
            prefix = adapter._store_prefix(seed / "server", "queue-smoke")
            prefix.mkdir(parents=True)
            slots = [prefix / (name + ".txt") for name in ("a", "b")]
            for index, slot in enumerate(slots):
                slot.write_text("PZSW\t1\t" + str(index + 19) + "\nEND\tfixture\n")
            foreign = adapter._store_prefix(seed / "server", "unrelated-world") / "a.txt"
            foreign.parent.mkdir(parents=True)
            foreign.write_text("do not restore another world")
            value = dict(selection("shared-wishlist", "reload"), options={"seed_run": str(seed)})
            with patch("queue_checks.report.verify_manifest", return_value=[]):
                self.assertEqual([state, *slots], adapter._seed(value)[1])
                output_runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(target / role)} for role in runtime["roles"]}}
                adapter.stage(ROOT, target, None, None, value, {}, output_runtime)
                self.assertEqual(state.read_bytes(), (target / state.relative_to(seed)).read_bytes())
                self.assertFalse((target / forbidden.relative_to(seed)).exists())
                self.assertFalse(adapter._store_prefix(target / "server", "queue-smoke").exists(), "Live userdata must be restored only after native launch")
                helpers = []
                for role in runtime["roles"]:
                    helper = target / role / "mods/WishlistTest/42/media/lua/server"
                    text = (helper / "WishlistSeedRestore.lua").read_text()
                    self.assertIn(str(target / "server/Saves/Multiplayer/queue-smoke"), text)
                    self.assertIn('PZSW\\t1\\t19', text)
                    self.assertNotIn("unrelated-world", text)
                    helpers.append(text)
                self.assertEqual(helpers, [helpers[0]] * 3)
                self.assertTrue(all(slot.read_text().startswith("PZSW") for slot in slots))
                self.assertEqual("reload", (target / "client1/Lua/wishlist-fixture.txt").read_text().splitlines()[1])
                with self.assertRaisesRegex(ValueError, "endpoint"):
                    adapter._seed(dict(value, ports=[19061, 19062]))
                evidence["report.json"]["status"] = "failed"
                (seed / "report.json").write_text(json.dumps(evidence["report.json"]))
                with self.assertRaisesRegex(ValueError, "verified successful"):
                    adapter._seed(value)
                clean = json.loads(json.dumps(evidence["report.json"]))
                clean["status"] = "passed"
                for status, runtime_status, microphone, available in (
                    ("unknown", "clean", False, True),
                    ("needs-review", "unknown", False, True),
                    ("needs-review", "new-errors", False, True),
                    ("needs-review", "unclassified-errors", True, True),
                    ("needs-review", "unclassified-errors", False, False),
                    ("passed", "new-errors", False, True),
                ):
                    bad = json.loads(json.dumps(clean))
                    bad["status"] = status
                    bad["runtime"].update(status=runtime_status, microphone=microphone)
                    bad["runtime"]["roles"]["server"]["available"] = available
                    (seed / "report.json").write_text(json.dumps(bad))
                    with self.assertRaisesRegex(ValueError, "verified successful"):
                        adapter._seed(value)
                pending = json.loads(json.dumps(clean))
                pending["status"] = "needs-review"
                pending["runtime"]["status"] = "unclassified-errors"
                (seed / "report.json").write_text(json.dumps(pending))
                self.assertEqual([state, *slots], adapter._seed(value)[1])
                for role in runtime["roles"]:
                    (target / (role + "-launch.log")).write_text(server_log(value) if role == "server" else client_log(value, role))
                result = adapter.verify(target, value, {"suites": adapter.definitions()})
                self.assertEqual([], result["issues"])
                self.assertTrue(result["evidence"]["requires_review"])
                self.assertTrue(result["evidence"]["seed_native_audit"]["pending"])
                evidence["execution.json"]["processes"]["server"].pop("exit_code")
                (seed / "execution.json").write_text(json.dumps(evidence["execution.json"]))
                with self.assertRaisesRegex(ValueError, "not stopped"):
                    adapter._seed(value)
                evidence["execution.json"]["processes"]["server"]["exit_code"] = 0
                (seed / "execution.json").write_text(json.dumps(evidence["execution.json"]))
            evidence["report.json"]["status"] = "passed"
            (seed / "report.json").write_text(json.dumps(evidence["report.json"]))
            with patch("queue_checks.report.verify_manifest", return_value=["Changed input"]):
                with self.assertRaisesRegex(ValueError, "evidence has changed"):
                    adapter._seed(value)


if __name__ == "__main__":
    unittest.main()
