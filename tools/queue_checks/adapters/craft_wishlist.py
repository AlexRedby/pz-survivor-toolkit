"""Run the preserved crafting/wishlist stages without replacing their assertions."""
import json
from pathlib import Path
import re
import shutil


COUNTS = {"crafting-plans": {"crafting": 20, "ui": 28, "alternatives": 23},
          "shared-wishlist": {"full": 33, "standalone": 26, "visual": 11, "reload": 5}}
HELPERS = {"crafting-plans": "CraftPlanTest", "shared-wishlist": "WishlistTest"}
PROJECT = Path(__file__).resolve().parents[3]
FULL_MODS = ["NeatUI_Framework", "CleanUI", "PZSurvivorToolkit", "EURY_CONTAINERS", "Neat_Crafting", "Project_Cook", "Neat_Building_UIOnly", "PZSurvivorWishlist"]


def definitions():
    result = {}
    for suite, counts in COUNTS.items():
        cases = [{"id": case, "producer": "preserved-" + suite, "capability": case,
                  "kinds": ["mp"], "modes": ["toolkit"] if suite == "crafting-plans" else ["toolkit", "native"],
                  "preserved_stages": count} for case, count in counts.items()]
        if suite == "shared-wishlist":
            for case in cases:
                case["default_mods"] = FULL_MODS if case["id"] == "full" else ["PZSurvivorWishlist"]
                if case["id"] != "full":
                    case["modes"] = ["toolkit"]
                    case["control_reason"] = "Wishlist-only scenario has no Toolkit queue option to disable"
        defaults = ["PZSurvivorWishlist"]
        if suite == "crafting-plans":
            defaults = ["NeatUI_Framework", "PZSurvivorToolkit", "Neat_Crafting", "PZSurvivorWishlist"]
        result[suite] = {"status": "ready", "native_validation": "not-run", "adapter": "craft_wishlist", "clients": 2,
                         "default_mods": defaults, "cases": cases,
                         "limits": ["MP callback-driven assertions; physical input and visual screenshot review remain separate."]}
    return result


def validate(selection):
    suite = selection["suite"]
    if selection["kind"] != "mp":
        raise ValueError("Preserved crafting/wishlist fixtures require two-client MP")
    if selection.get("clients", 2) != 2:
        raise ValueError("Preserved crafting/wishlist fixtures require exactly two clients")
    if len(selection["cases"]) != 1 or selection["cases"][0] not in COUNTS[suite]:
        raise ValueError("Choose exactly one preserved scenario per isolated lifecycle")
    if selection["ports"][1] != selection["ports"][0] + 1:
        raise ValueError("Preserved fixtures require an adjacent UDP port")
    case = selection["cases"][0]
    mods = selection["mods"]
    if "PZSurvivorWishlist" not in mods:
        raise ValueError("Preserved fixtures require PZSurvivorWishlist")
    if suite == "crafting-plans":
        if selection["mode"] != "toolkit":
            raise ValueError("Craft plan operations require the toolkit queue API")
        for required in ("PZSurvivorToolkit", "NeatUI_Framework", "Neat_Crafting"):
            if required not in mods:
                raise ValueError("Craft plan dependency missing: " + required)
    elif case in ("standalone", "visual", "reload"):
        if selection["mode"] != "toolkit":
            raise ValueError("Wishlist-only scenario has no Toolkit queue option to disable")
        if mods != ["PZSurvivorWishlist"]:
            raise ValueError("Wishlist standalone/visual/reload requires only PZSurvivorWishlist")
        if case == "reload":
            _seed(selection)
    else:
        for required in FULL_MODS:
            if required not in mods:
                raise ValueError("Wishlist full integration missing: " + required)


def sources(project, selection):
    source = Path(project) / "tests/native_queue/contributions" / selection["suite"]
    paths = sorted(path for path in source.rglob("*") if path.is_file() and path.suffix in (".py", ".lua", ".json"))
    if selection["suite"] == "shared-wishlist" and selection["cases"] == ["reload"]:
        seed, state = _seed(selection)
        paths.append(Path(project) / "tests/native_queue/support/QueueWishlistRestore.lua")
        paths += [seed / name for name in ("selection.json", "runtime.json", "execution.json", "report.json", "source-manifest.json", "snapshot-hashes.json")]
        paths += [seed / (role + "-launch.log") for role in ("server", "client1", "client2")]
        paths += [path for path in state if path.is_file()]
    return paths


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    if set(runtime["roles"]) != {"server", "client1", "client2"}:
        raise ValueError("Preserved fixtures require server/client1/client2 caches")
    source = Path(project) / "tests/native_queue/contributions" / selection["suite"] / "prepare.py"
    namespace = {"__file__": str(source), "__name__": "preserved_" + selection["suite"]}
    exec(compile(source.read_text(), str(source), "exec"), namespace)
    if selection["suite"] == "shared-wishlist" and selection["cases"] == ["full"]:
        if not any(list(Path(source).rglob("BetterContainers/Proximity.lua")) for source in locations.values()):
            raise ValueError("Wishlist full requires the selected BetterContainers/Proximity implementation")
    for role in runtime["roles"]:
        cache = Path(output) / role
        args = [cache, role, selection["cases"][0], "127.0.0.1", selection["ports"][0], "smoke-local-only"]
        if selection["suite"] == "shared-wishlist":
            args.append(selection["mods"])
        namespace["prepare"](*args)
    if selection["suite"] == "shared-wishlist" and selection["cases"] == ["reload"]:
        seed, state = _seed(selection)
        name = json.loads((seed / "runtime.json").read_text())["server_name"]
        if runtime["server_name"] != name:
            raise ValueError("Wishlist reload must preserve the seed server name")
        prefix = _store_prefix(seed / "server", name)
        slots = {}
        for source in state:
            if source.is_file():
                if source.parent == prefix:
                    text = source.read_text(encoding="utf-8")
                    if any(ord(char) < 32 and char not in "\t\r\n" for char in text):
                        raise ValueError("Invalid control character in wishlist seed store")
                    slots[source.stem] = text
                    continue
                target = Path(output) / source.relative_to(seed)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        from ..native import _lua
        config = {"world": str(Path(output) / "server/Saves/Multiplayer" / name), "slots": slots}
        # Kahlua truncates raw non-ASCII literals before decoding their saved bytes as UTF-8.
        input_lua = "".join(char if ord(char) < 128 else "".join(f"\\{byte:03d}" for byte in char.encode("utf-8"))
                            for char in _lua(config))
        for role in runtime["roles"]:
            helper = Path(output) / role / "mods/WishlistTest/42/media/lua/server"
            shutil.copy2(Path(project) / "tests/native_queue/support/QueueWishlistRestore.lua", helper)
            (helper / "WishlistSeedRestore.lua").write_text(
                "local Restore=require 'QueueWishlistRestore'\nlocal input=" + input_lua +
                "\nWishlistSeedRestore=function() Restore(input.world,input.slots) end\n", encoding="utf-8")
    runtime["fixture"] = {"mods": [HELPERS[selection["suite"]]], "server_ready": server_ready(selection),
                          "sandbox": server_settings(selection), "client_launch_stagger_seconds": 8,
                          "queue_control": "intrinsic toolkit operation API" if selection["suite"] == "crafting-plans" else "queue toggle if Toolkit is selected; standalone product otherwise"}


def server_settings(selection):
    return {"MinutesPerPage": 0.02 if selection["suite"] == "crafting-plans" else 2.0}


def server_ready(selection):
    return "[QUEUE_TEST] SERVER_READY" if selection["suite"] == "crafting-plans" else "[WISHLIST_TEST] SERVER_READY"


def marker(selection):
    return "CRAFT_TEST" if selection["suite"] == "crafting-plans" else "WISHLIST_TEST"


def complete(selection, role, text):
    # Completion ends the lifecycle; the verifier separately rejects partial/failed stages.
    return bool(re.search(r"\[" + marker(selection) + r"\] COMPLETE checks=\d+ failures=\d+(?:\s|$)", text))


def _client_issues(text, selection, role, case):
    prefix = r"\[" + marker(selection) + r"\] "
    expected = COUNTS[selection["suite"]][case]
    issues = []
    completed = re.findall(prefix + r"COMPLETE checks=(\d+) failures=(\d+)(?:\s|$)", text)
    passes = re.findall(prefix + r"PASS (.+?) nil(?:\r?$)", text, re.M)
    if completed != [(str(expected), "0")]:
        issues.append(role + ": expected exactly one successful " + case + " completion")
    names = json.loads((PROJECT / "tests/native_queue/contributions" / selection["suite"] / "stage-names.json").read_text())[case]
    if passes != names:
        issues.append(role + ": missing, duplicate, reordered or unknown preserved " + case + " stage assertions")
    if re.search(prefix + r"FAIL(?:\s|$)", text) or "[QUEUE_TEST] FAIL " in text:
        issues.append(role + ": fixture failure")
    if completed and passes:
        last_pass = list(re.finditer(prefix + r"PASS ", text))[-1].start()
        if last_pass > text.find("[" + marker(selection) + "] COMPLETE"):
            issues.append(role + ": completion precedes preserved stages")
    language = "EN" if role == "client1" else "RU"
    if not re.search(prefix + r"CONNECTED " + role + " language=" + language + r"(?:\s|$)", text):
        issues.append(role + ": missing connected actor/language marker")
    if selection["suite"] == "crafting-plans":
        # Native MP reloads Lua before entering the world, repeating this bootstrap banner.
        if set(re.findall(prefix + r"EXPECTED checks=(\d+) scenario=(\w+)", text)) != {(str(expected), case)}:
            issues.append(role + ": expected scenario/count differs")
        if case == "ui":
            required = ["PREVIEW_RENDERED", "FALLBACK_RENDERED", "WINDOW_GUARDS", "START_CALLBACK"]
            for name in required:
                if not re.search(prefix + name + " " + role + r"(?:\s|$)", text):
                    issues.append(role + ": missing UI evidence " + name)
            for label in ("constrained", "scrolled", "short", "wide"):
                if not re.search(prefix + "SCROLLBAR_BOUNDS " + role + " label=" + label + r"(?:\s|$)", text):
                    issues.append(role + ": missing native scrollbar evidence " + label)
    return issues


def _server_issues(text, selection, case):
    issues = []
    if len(re.findall(re.escape(server_ready(selection)) + r"(?:\s|$)", text)) != 1:
        issues.append("server: expected exactly one native readiness marker")
    required = []
    if selection["suite"] == "crafting-plans":
        if case == "crafting":
            required = ["SERVER_" + phase + "_VERIFY " + role + " ok=true error=nil" for phase in ("CANCEL", "CHAIN") for role in ("client1", "client2")]
            required.append("SERVER_RACE_VERIFY ok=true completed=1 error=nil")
        elif case == "alternatives":
            required = ["SERVER_ALTERNATIVES_VERIFY " + role + " phase=" + phase + " ok=true error=nil" for role in ("client1", "client2") for phase in ("chain", "repeat", "logs")]
    for receipt in required:
        if len(re.findall(r"\[CRAFT_TEST\] " + re.escape(receipt) + r"(?:\s|$)", text)) != 1:
            issues.append("server: missing, duplicate or failed authority receipt " + receipt)
    if selection["suite"] == "shared-wishlist" and case in ("full", "standalone"):
        for role in ("client1", "client2"):
            if len(re.findall(r"\[WISHLIST_TEST\] SERVER_VERIFY " + role + r" ok=true(?:\s|$)", text)) != 1:
                issues.append("server: missing, duplicate or failed wishlist authority receipt " + role)
    if selection["suite"] == "shared-wishlist" and case == "reload":
        slots = re.findall(r"\[WISHLIST_TEST\] RESTORE slot=([ab]) chars=([1-9][0-9]*)(?:\s|$)", text)
        completed = re.findall(r"\[WISHLIST_TEST\] RESTORE_COMPLETE slots=([12])(?:\s|$)", text)
        if not slots or len({slot for slot, _ in slots}) != len(slots) or completed != [str(len(slots))]:
            issues.append("server: missing, duplicate or inconsistent wishlist restore receipts")
        elif text.index("[WISHLIST_TEST] RESTORE_COMPLETE") > text.index(server_ready(selection)):
            issues.append("server: wishlist restore completed after readiness")
    if re.search(r"\[(?:CRAFT_TEST|WISHLIST_TEST|QUEUE_TEST)\] FAIL(?:\s|$)", text):
        issues.append("server: fixture failure")
    if re.search(r"\[(?:CRAFT_TEST|WISHLIST_TEST)\] SERVER_[A-Z_]*VERIFY [^\n]*ok=false(?:\s|$)", text):
        issues.append("server: failed authority receipt")
    return issues


def verify(root, selection, catalog):
    root = Path(root)
    case = selection["cases"][0]
    coverage = []
    specs = {row["id"]: row for row in catalog["suites"][selection["suite"]]["cases"]}
    server = root / "server-launch.log"
    issues = _server_issues(server.read_text(errors="replace") if server.is_file() else "", selection, case)
    for role in ("client1", "client2"):
        path = root / (role + "-launch.log")
        text = path.read_text(errors="replace") if path.is_file() else ""
        issues.extend(_client_issues(text, selection, role, case))
    for role in ("client1", "client2"):
        failed = any(issue.startswith(role + ":") or issue.startswith("server:") for issue in issues)
        spec = specs[case]
        coverage.append({"suite": selection["suite"], "case": case, "producer": spec["producer"], "capability": spec["capability"],
                         "kind": selection["kind"], "mode": selection["mode"], "actor": role, "status": "failed" if failed else "passed",
                         "outcome": {"preserved_stages": COUNTS[selection["suite"]][case]}})
    evidence = {"preserved_stages_per_client": COUNTS[selection["suite"]][case],
                "source": "tests/native_queue/contributions/" + selection["suite"],
                "visual_review": "Screenshots must be inspected separately; callback success does not certify pixels."}
    if selection["suite"] == "shared-wishlist" and case == "reload":
        seed, _ = _seed(selection)
        initial = json.loads((seed / "report.json").read_text())
        pending = initial["status"] == "needs-review"
        evidence["seed_native_audit"] = {"run": str(seed), "status": initial["status"],
                                         "runtime_status": initial["runtime"]["status"], "pending": pending}
        evidence["requires_review"] = pending
    return {"issues": issues, "outcomes": coverage, "evidence": evidence}


def _store_prefix(cache, name):
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", name) or name in (".", ".."):
        raise ValueError("Invalid wishlist seed server name")
    # Kahlua string.byte returns Java UTF-16 code units, not UTF-8 bytes.
    raw = str(cache / "Saves/Multiplayer" / name).encode("utf-16-be")
    encoded = "".join(f"{int.from_bytes(raw[i:i+2], 'big'):04x}" for i in range(0, len(raw), 2))
    return cache / "Lua/PZSurvivorWishlist" / Path(*[encoded[i:i+80] for i in range(0, len(encoded), 80)])


def _seed(selection):
    value = selection.get("options", {}).get("seed_run")
    if not value:
        raise ValueError("Wishlist reload requires options.seed_run from a completed full/standalone run")
    root = Path(value).resolve()
    try:
        initial, runtime, execution, report = [json.loads((root / name).read_text()) for name in ("selection.json", "runtime.json", "execution.json", "report.json")]
    except (OSError, ValueError) as error:
        raise ValueError("Cannot read wishlist persistence seed evidence") from error
    if not all(isinstance(value, dict) for value in (initial, runtime, execution, report)):
        raise ValueError("Wishlist seed evidence must contain JSON objects")
    audit = report.get("runtime", {})
    if not isinstance(audit, dict) or not isinstance(audit.get("roles"), dict):
        raise ValueError("Wishlist seed must have verified successful runtime evidence")
    audit_roles = audit.get("roles", {})
    pending = report.get("status") == "needs-review" and audit.get("status") == "unclassified-errors"
    accepted = report.get("status") == "passed" and audit.get("status") in ("clean", "background-only")
    if (initial.get("suite") != "shared-wishlist" or initial.get("cases") not in (["full"], ["standalone"])
            or execution.get("status") != "completed" or not (accepted or pending)
            or audit.get("microphone") is not False or set(audit_roles) != {"server", "client1", "client2"}
            or any(not isinstance(row, dict) or row.get("available") is not True for row in audit_roles.values())
            or not report.get("provenance", {}).get("verified") or report.get("functional", {}).get("status") != "passed"):
        raise ValueError("Wishlist reload seed must have verified successful full/standalone native evidence")
    if initial.get("ports") != selection["ports"]:
        raise ValueError("Wishlist reload must preserve the seed endpoint for native client save identities")
    from ..report import verify_manifest, audit_logs
    if verify_manifest(root, "source-manifest.json", True) or verify_manifest(root, "snapshot-hashes.json"):
        raise ValueError("Wishlist seed source/snapshot evidence has changed")
    # Runtime logs remain writable after report.json; a stale green report is not a safe seed.
    fresh = audit_logs(root, ("server", "client1", "client2"))
    if any(not row["available"] or row["microphone"] or row["fatal_count"] or
           (row["unclassified_count"] and not pending) for row in fresh.values()):
        raise ValueError("Wishlist seed runtime audit is unsafe or stale")
    initial_case = initial["cases"][0]
    for role in ("server", "client1", "client2"):
        if execution.get("processes", {}).get(role, {}).get("exit_code") is None:
            raise ValueError("Wishlist persistence seed processes were not stopped")
        log = root / (role + "-launch.log")
        if not log.is_file():
            raise ValueError("Wishlist seed native logs are missing")
        text = log.read_text(errors="replace")
        issues = _server_issues(text, initial, initial_case) if role == "server" else _client_issues(text, initial, role, initial_case)
        if issues:
            raise ValueError("Wishlist seed native assertions are incomplete: " + "; ".join(issues))
    state = []
    for role in ("server", "client1", "client2"):
        cache = root / role
        if Path(runtime["roles"][role]["cache"]).resolve() != cache:
            raise ValueError("Wishlist seed caches must belong to the supplied run")
        for directory in (cache / "Saves", cache / "db"):
            if directory.is_symlink():
                raise ValueError("Wishlist seed state cannot contain symlinks")
            if directory.exists():
                for path in directory.rglob("*"):
                    if path.is_symlink():
                        raise ValueError("Wishlist seed state cannot contain symlinks")
                    if path.is_file():
                        state.append(path)
    if not any(path.is_relative_to(root / "server/Saves") for path in state):
        raise ValueError("Wishlist seed has no persisted server world")
    cache = root / "server"
    prefix = _store_prefix(cache, runtime.get("server_name"))
    if any(path.is_symlink() for path in (prefix, *prefix.parents) if path.is_relative_to(cache)):
        raise ValueError("Wishlist seed store cannot contain symlinks")
    slots = []
    for name in ("a", "b"):
        path = prefix / (name + ".txt")
        if path.is_symlink() or path.exists() and not path.is_file():
            raise ValueError("Wishlist seed store must contain regular slot files")
        if path.is_file():
            slots.append(path)
    if not slots:
        raise ValueError("Wishlist seed has no persisted product store for its owned world")
    state += slots
    return root, state
