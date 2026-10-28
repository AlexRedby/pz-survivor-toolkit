"""Exact scenario results, bounded log auditing and comparable native controls."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
from . import adapters


MARKER = "[QUEUE_CHECK] "
RECORD = re.compile(r"^\s*(?:LOG|WARN|ERROR|DEBUG|TRACE)\s*:")
# Some native script errors use DebugLog.General.println with ERROR in the payload.
GENERAL_ERROR = re.compile(r"^\s*LOG\s*:\s*General\b[^>\r\n]*>\s*ERROR\s*:")
STAMP = re.compile(r"^\s*\[\d{2}-\d{2}-\d{2,4}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?\]\s*")
MIC = ("System create record sound", "initialisedRecDev=true", "fmodRecordSound=", "Microphone was not disabled")
RECEIPT = re.compile(r"HEALTH_AUTH_RECEIPT (\S*) phase=(\w+) ok=(true|false) patient=(\S*) error=([^\n]+)")
HEALTH_COMPLETION_CASES = {'bandageApply', 'glassHands', 'stitchApply', 'expandedCancel', 'missingChildSupply', 'nativeStop', 'miniReplaceBag'}
SESSION = re.compile(r"\[QUEUE_SESSION\] (BEGIN|START|FINISH|CLEANUP|JOINT_CLEAN|COMPLETE|QUARANTINE) case=(\S+) epoch=(\d+) actor=(\S+)(?:\s|$)")
ANTICHEAT_KICK = re.compile(
    r'^\s*WARN\s*:\s*Multiplayer\b.*\bat AntiCheat\.log\s*>\s*Anti-cheat="[^"\r\n]+" '
    r'is triggered for connection="[^"\r\n]*" .*\bcounter=(\d+)/(\d+) action="Kick"(?:\s|$)')
EXCEPTION = re.compile(r"\b[\w.$]+(?:Exception|Error):"
                       r"|(?:^|\n)\s*(?:Exception in thread \"[^\"]+\"\s+)?(?:[\w$]+\.)+(?:[\w$]+(?:Exception|Error)|Exception|Error)(?:\s|$)"
                       r"|(?:^|\n)\s*KahluaException(?:\s|$)")
RUNTIME_FAILURE = re.compile(
    r"\b(?:OutOfMemoryError|EXCEPTION_ACCESS_VIOLATION|SIGSEGV|SIGBUS|SQLITE_(?:CORRUPT|NOTADB|FULL|IOERR))\b"
    r"|(?:failed|unable|cannot|could not) (?:to )?(?:bind|save|write|connect)\b"
    r"|database (?:disk image is malformed|is locked|is corrupt)|checksum mismatch", re.I)
BACKGROUND_GAME_SHA256 = "e1a69eb743ede60b213a0fe7f8b83d4fcab773036d256cc4543a336f3b058a33"
KNOWN_ROOM_GAME_SHA256 = BACKGROUND_GAME_SHA256  # Native B42.21.0 revision 4a0e9546ec only.
GAME_INPUT_TREES = ('media/lua', 'media/scripts')
THUMP_TILES = ({"fencing_01_" + str(i) for i in
                (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 24, 25, 26, 27, 28, 32, 33, 34, 35, 36,
                 40, 41, 42, 56, 57, 58, 59, 60, 64, 65, 66, 67, 68, 72, 73, 75)} |
               {"carpentry_02_" + str(i) for i in (40, 41, 44, 45, 48, 49)})


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def game_inputs(game):
    """Seal live Lua/script trees; binary and other asset trees are outside this scope."""
    game = Path(game).resolve()
    trees = {}
    for tree in GAME_INPUT_TREES:
        root, files = game / tree, {}
        for path in [game / 'media', root, *sorted(root.rglob('*'))]:
            if path.is_symlink():
                raise ValueError('Native game input symlinks are unsupported: ' + str(path))
            if path.is_file():
                files[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
        trees[tree] = files
    return {'game': str(game), 'trees': trees}


def verify_game_inputs(root):
    try:
        expected = read_json(root / 'game-inputs.json')
        game = read_json(root / 'runtime.json')['game']
        if (not isinstance(game, str) or not Path(game).is_absolute() or not isinstance(expected, dict)
                or expected.get('game') != game or not isinstance(expected.get('trees'), dict)
                or set(expected['trees']) != set(GAME_INPUT_TREES)
                or any(not isinstance(files, dict) for files in expected['trees'].values())):
            return ['Invalid native game input seal; prepare a fresh snapshot']
        actual = game_inputs(game)
        errors = []
        for tree in GAME_INPUT_TREES:
            before, after = expected['trees'][tree], actual['trees'][tree]
            for name in sorted(before.keys() | after.keys()):
                if name not in before:
                    errors.append('Added native game input: ' + tree + '/' + name)
                elif name not in after:
                    errors.append('Missing native game input: ' + tree + '/' + name)
                elif before[name] != after[name]:
                    errors.append('Changed native game input: ' + tree + '/' + name)
        return errors
    except (OSError, ValueError, KeyError, TypeError) as error:
        return ['Cannot verify native Lua/script inputs; prepare a fresh snapshot: ' + str(error)]


def verify_manifest(root, filename, absolute=False):
    root = Path(root).resolve()
    errors = []
    try:
        manifest = read_json(root / filename)
    except (OSError, ValueError) as error:
        return ["Cannot read manifest " + filename + ": " + str(error)]
    if not isinstance(manifest, dict) or not manifest:
        return ["Manifest is empty or invalid: " + filename]
    for name, expected in manifest.items():
        if not isinstance(name, str) or not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            errors.append("Invalid manifest entry: " + str(name)); continue
        path = Path(name) if absolute else root / name
        if absolute and not path.is_absolute():
            errors.append("Source manifest requires absolute path: " + name); continue
        if not absolute and not path.resolve().is_relative_to(root):
            errors.append("Manifest path escapes run: " + name)
            continue
        if not path.is_file():
            errors.append("Missing input: " + str(path))
        elif hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            errors.append("Changed input: " + str(path))
    if filename == 'source-manifest.json' and absolute:
        errors += verify_game_inputs(root)
    if filename == "snapshot-hashes.json" and not absolute:
        required = {"selection.json", "runtime.json", "settings-fingerprint.json", "source-manifest.json", "manifest.json", "initial-settings.json", "game-inputs.json"}
        missing = required - manifest.keys()
        if missing:
            errors.append("Snapshot metadata missing: " + ", ".join(sorted(missing)))
        try:
            selection = read_json(root / "selection.json")
            roles = adapters.roles(selection)
            # Lua/ is writable user data: pin prepared inputs, permit native-generated layouts/options.
            actual = {path.relative_to(root).as_posix() for role in roles for sub in ("mods", "classes")
                      for path in (root / role / sub).rglob("*") if path.is_file()}
            declared = {name for name in manifest if any(name.startswith(role + "/" + sub + "/")
                        for role in roles for sub in ("mods", "classes"))}
            if actual != declared:
                errors.append("Frozen file set differs: added=" + str(sorted(actual - declared)) + "; missing=" + str(sorted(declared - actual)))
            for role in roles:
                for sub in ("mods", "Lua"):
                    if not any(name.startswith(role + "/" + sub + "/") for name in manifest):
                        errors.append("Frozen inputs missing: " + role + "/" + sub)
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append("Cannot verify frozen file set: " + str(error))
    return errors


def events(text):
    result = []
    for number, line in enumerate(text.splitlines(), 1):
        if MARKER not in line:
            continue
        try:
            value = json.loads(line.split(MARKER, 1)[1])
        except json.JSONDecodeError as error:
            raise ValueError("Invalid structured event at line " + str(number)) from error
        if not isinstance(value, dict) or value.get("event") not in ("setup", "case", "complete", "error"):
            raise ValueError("Invalid event envelope at line " + str(number))
        result.append(value)
    return result


def log_paths(root, role):
    paths = [root / (role + "-launch.log"), root / (role + "-probes.log"), root / role / "console.txt"]
    # Host's server startup archives the owner's earlier client log in the shared cache.
    paths += [path for path in sorted((root / role / "Logs").rglob("*DebugLog*.txt"))
              if role != 'client1' or not path.name.endswith('DebugLog-server.txt')]
    return [path for path in paths if path.is_file()]


def background_profile(root, selection, verified):
    """Only the two source-verified profiles whose startup fallbacks were inspected."""
    if not verified or selection.get("suite") != "animal-trailer" or selection.get("kind") != "mp" or selection.get("clients") != 1 or selection.get("languages") != ["EN"] or selection.get("cases") not in (["equipment-fixed"], ["equipment-missing"]):
        return False
    expected = ["ZombieBuddy", "PZSurvivorToolkit"]
    if selection["cases"] == ["equipment-fixed"]:
        expected.insert(1, "PZToolkitJavaPatches")
    if selection.get("mods") != expected:
        return False
    try:
        game = Path(read_json(root / "runtime.json")["game"])
        return read_json(root / "source-manifest.json").get(str(game / "projectzomboid.jar")) == BACKGROUND_GAME_SHA256
    except (OSError, ValueError, KeyError, TypeError):
        return False


def verified_game_sha256(root, verified):
    """The caller has verified both manifests, including the actual game JAR and runtime path."""
    if not verified:
        return None
    try:
        game = Path(read_json(root / "runtime.json")["game"])
        if game.is_absolute():
            digest = read_json(root / "source-manifest.json").get(str(game / "projectzomboid.jar"))
            if digest == KNOWN_ROOM_GAME_SHA256:
                return digest
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None


def background_rule(block, role):
    message = block[0].split(">", 1)[-1].strip().rstrip(".")
    text = "\n".join(block)
    if not any(line.strip() for line in block[1:]) and not EXCEPTION.search(text) and not RUNTIME_FAILURE.search(text):
        if re.search(r"\bat FluidContainerScript\.load\s*>", block[0]) and message in (
                "Sanitizing container name 'Large Bucket', name may not contain whitespaces",
                "Sanitizing container name 'Fuel Pump', name may not contain whitespaces"):
            return "fluid-name-normalization", 1 if role == "server" else 2
        if role == "server" and re.search(r"\bat BrokenFences\.addBrokenTiles\s*>", block[0]) and message.startswith("Missing ThumpSound for breakable object ") and message.removeprefix("Missing ThumpSound for breakable object ") in THUMP_TILES:
            return "default-fence-break-sound", 1
        if re.search(r"\bat CraftRecipeComponentScript\.getIconTexture\s*>", block[0]) and message == "CraftRecipeComponentScript: Recipe Piano missing UiConfigScript - falling back to SpriteConfigScript first world object face for recipe icon":
            return "piano-icon-fallback", 1
    if role == "server" and message == "IsoPropertyType.lookupOrDefaultStr> Exception thrown":
        body = [line.strip().rstrip(".") for line in block[1:] if line.strip()]
        frames = ["Stack trace:", "zombie.core.properties.IsoPropertyType.lookup(IsoPropertyType.java:273)",
                  "zombie.core.properties.IsoPropertyType.lookupOrDefaultStr(IsoPropertyType.java:281)",
                  "zombie.core.TilePropertyAliasMap.register(TilePropertyAliasMap.java:54)",
                  "zombie.core.TilePropertyAliasMap.Generate(TilePropertyAliasMap.java:27)",
                  "zombie.iso.IsoWorld.GenerateTilePropertyLookupTables(IsoWorld.java:1337)",
                  "zombie.iso.IsoWorld.init(IsoWorld.java:2257)", "zombie.network.GameServer.main(GameServer.java:817)"]
        for name in ("ladderW", "ladderS", "ladderE", "ladderN", "WindowShape"):
            cause = "zombie.core.properties.IsoPropertyType$IsoPropertyTypeNotFoundException: Property Name not found: " + name + " at IsoPropertyType.lookup(IsoPropertyType.java:273). Message: Property Name not found: " + name
            if body == [cause, *frames]:
                return "property-name-string-fallback", 1
    return None


def audit_log(path, cache, background=False, native_game_sha256=None):
    """Keep counts within a file; mirrors are merged using max, never summed."""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    findings, microphone = [], []
    for number, line in enumerate(lines, 1):
        for marker in MIC:
            if marker in line and not (marker == "fmodRecordSound=" and re.search(r"fmodRecordSound=0(?:\s|$|[,;}])", line)):
                microphone.append({"file": str(path), "line": number, "message": line})
    lines = [STAMP.sub("", line) for line in lines]
    marker = "[ANIMAL_TRAILER] SERVER READY" if cache.name == "server" else "[ANIMAL_TRAILER] CLIENT INGAME"
    ready = next((i for i, line in enumerate(lines) if marker in line), None)
    starts = [i for i, line in enumerate(lines) if RECORD.match(line)]
    if lines and (not starts or starts[0] != 0):
        starts.insert(0, 0)
    for index, start in enumerate(starts):
        block = lines[start:starts[index + 1] if index + 1 < len(starts) else len(lines)]
        kick = ANTICHEAT_KICK.match(block[0])
        # Kick names the configured policy even before the counter reaches its enforcement threshold.
        terminal_kick = kick is not None and 0 < int(kick[2]) <= int(kick[1])
        text = "\n".join(block)
        serious = bool(terminal_kick or EXCEPTION.search(text) or RUNTIME_FAILURE.search(text))
        is_error = re.match(r"^\s*ERROR\s*:", block[0]) or GENERAL_ERROR.match(block[0]) or serious
        if not is_error:
            continue
        message = block[0].split(">", 1)[-1].strip()
        cause = next((line.strip() for line in block[1:] if re.search(r"(?:Exception|Error)(?::|\b)", line)), "")
        message = message.replace(str(cache), "<cache>")
        cause = cause.replace(str(cache), "<cache>")
        # DebugLog's formatter can append a second full stop to a mirrored console message.
        key = message.rstrip(".") + ("\n" + cause.rstrip(".") if cause else "")
        rule = background_rule(block, cache.name) if not terminal_kick and background and ready is not None and start < ready else None
        if (native_game_sha256 == KNOWN_ROOM_GAME_SHA256 and not serious
                and not any(line.strip() for line in block[1:])
                and re.fullmatch(r"\s*ERROR\s*:\s*General\b[^>\r\n]*\bat Basements\.mergeRoomsOntoMetaCell\s*>\s*"
                                 r"duplicate RoomDef\.metaID for room at 10707,9484,0\.{0,2}\s*", block[0])):
            rule = ("known-upstream-b42.21-room-metaid", None)
        findings.append({"fingerprint": hashlib.sha256(key.encode()).hexdigest(), "message": message,
                         "cause": cause, "file": str(path), "line": start + 1,
                         "severity": "background" if rule else "fatal" if serious else "unclassified",
                         "background_rule": rule[0] if rule else None, "background_limit": rule[1] if rule else None,
                         "category": "lua" if "Kahlua" in key or "Lua(" in key else "native"})
    counts = Counter(row["fingerprint"] for row in findings)
    for row in findings:
        if (row["severity"] == "background" and row["background_limit"] is not None
                and counts[row["fingerprint"]] > row["background_limit"]):
            row["severity"] = "unclassified"
    return findings, microphone


def diagnostic_windows(logs):
    """Place existing findings by local markers; this never changes the full runtime audit."""
    merged, details, cases = {}, {}, set()
    marked = False
    for path, findings in logs:
        markers = [(number, match) for number, line in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1)
                   if (match := SESSION.search(line))]
        has_begin = any(match[1] == 'BEGIN' for _, match in markers)
        marked |= has_begin
        phase, active = 'startup' if has_begin else 'unassigned', None
        boundaries = [(0, (phase, None, None))]
        for number, match in markers if has_begin else []:
            event, case, epoch, _actor = match.groups()
            identity = (case, int(epoch))
            if event == 'BEGIN':
                active, phase = identity, 'run'
                cases.add(identity)
            elif identity != active:
                continue
            elif event == 'START':
                phase = 'run'
            elif event in ('FINISH', 'CLEANUP'):
                phase = 'cleanup'
            elif event in ('JOINT_CLEAN', 'COMPLETE'):
                phase = 'between_cases'
            # QUARANTINE leaves the current diagnostic phase; functional validation owns its verdict.
            key = (phase, *active) if phase in ('run', 'cleanup') else (phase, None, None)
            boundaries.append((number, key))
        per_file, per_details = {}, {}
        index = 0
        for finding in findings:
            while index + 1 < len(boundaries) and boundaries[index + 1][0] <= finding['line']:
                index += 1
            key = boundaries[index][1]
            per_file.setdefault(key, Counter())[finding['fingerprint']] += 1
            per_details[(key, finding['fingerprint'])] = finding
        for key, counts in per_file.items():
            current = merged.setdefault(key, Counter())
            for fingerprint, count in counts.items():
                if count > current[fingerprint]:
                    details[(key, fingerprint)] = per_details[(key, fingerprint)]
            current |= counts
    if not marked:
        return None
    def bucket(key):
        counts = merged.get(key, Counter())
        return {'error_count': sum(counts.values()),
                'issues': [dict(details[(key, fingerprint)], count=count) for fingerprint, count in sorted(counts.items())]}
    return {'startup': bucket(('startup', None, None)),
            'cases': [{'case': case, 'epoch': epoch, 'run': bucket(('run', case, epoch)),
                       'cleanup': bucket(('cleanup', case, epoch))} for case, epoch in sorted(cases, key=lambda item: (item[1], item[0]))],
            'between_cases': bucket(('between_cases', None, None)), 'unassigned': bucket(('unassigned', None, None)),
            'interpretation': 'File-local marker placement only, not case verdicts or causes. Buckets are not additive when unmarked mirrors remain unassigned.'}


def audit_logs(root, roles, background=False, native_game_sha256=None, hosted=False):
    result = {}
    for role in roles:
        merged, details, microphone, logs = Counter(), {}, [], []
        paths = log_paths(root, role)
        for path in paths:
            cache = root / ('client1' if hosted and role == 'server' else role)
            findings, mic = audit_log(path, cache, background, native_game_sha256)
            logs.append((path, findings))
            current = Counter(row["fingerprint"] for row in findings)
            merged |= current
            for row in findings:
                previous = details.get(row["fingerprint"])
                rank = {"background": 0, "unclassified": 1, "fatal": 2}
                if previous is None or rank[row["severity"]] >= rank[previous["severity"]]:
                    details[row["fingerprint"]] = row
            microphone.extend(mic)
        result[role] = {"files": list(map(str, paths)), "issues": [dict(details[key], count=count) for key, count in sorted(merged.items())],
                        "error_count": sum(merged.values()), "microphone": microphone,
                        "available": bool(paths) and any(path.stat().st_size for path in paths)}
        windows = diagnostic_windows(logs)
        if windows is not None:
            result[role]['diagnostic_windows'] = windows
        for severity in ("fatal", "unclassified", "background"):
            result[role][severity + "_count"] = sum(count for key, count in merged.items() if details[key]["severity"] == severity)
    return result


def functional(root, selection, catalog):
    if adapters.get(selection['suite']):
        return adapters.functional(root, selection, catalog)
    roles = ["client1"] if selection["kind"] == "sp" else ["client1", "client2"]
    coverage, issues, clients = [], [], {}
    authority_path = root / ("server-launch.log" if selection["kind"] == "mp" else "client1-launch.log")
    authority = authority_path.read_text(errors="replace") if authority_path.is_file() else ""
    receipts = RECEIPT.findall(authority)
    specs = {case["id"]: case for case in catalog["suites"][selection["suite"]]["cases"]}
    for role in roles:
        path = root / (role + "-launch.log")
        text = path.read_text(errors="replace") if path.is_file() else ""
        try:
            records = events(text)
        except ValueError as error:
            issues.append(role + ": " + str(error)); records = []
        cases = [event for event in records if event["event"] == "case"]
        setup = [event for event in records if event["event"] == "setup"]
        complete = [event for event in records if event["event"] == "complete"]
        for event in records:
            if any(event.get(key) != expected for key, expected in
                   (("actor", role), ("suite", selection["suite"]), ("kind", selection["kind"]), ("mode", selection["mode"]))):
                issues.append(role + ": event actor/suite/kind/mode differs from selection")
        if len(setup) != 1 or not records or records[0]["event"] != "setup":
            issues.append(role + ": exactly one initial setup event required")
        if setup:
            start = setup[0]
            language = selection["languages"][-1] if role == "client2" else selection["languages"][0]
            if start.get("cases") != selection["cases"] or type(start.get("expected")) is not int or start.get("expected") != len(selection["cases"]) or start.get("nativeDurations") is not True or start.get("queueEnabled") is not (selection["mode"] == "toolkit") or start.get("language") != language:
                issues.append(role + ": setup cases/settings/language differ from selection")
        if [event.get("id") for event in cases] != selection["cases"]:
            issues.append(role + ": case events missing, duplicated or out of order")
        if len(complete) != 1:
            issues.append(role + ": exactly one completion event required")
        if not records or records[-1]["event"] != "complete":
            issues.append(role + ": completion must follow all cases")
        if "[QUEUE_TEST] FAIL " in text or any(event["event"] == "error" for event in records):
            issues.append(role + ": fixture failure")
        for marker in ("VOICE_DISABLED", "DISPLAY_READY", "PREFLIGHT_COMPLETE", "TRUE_SP" if selection["kind"] == "sp" else "NATIVE_CONNECTED"):
            if not re.search(r"\[QUEUE_TEST\] " + marker + r"(?:\s|$)", text):
                issues.append(role + ": missing readiness marker " + marker)
        counts = Counter()
        for event in cases:
            identifier, status = event.get("id"), event.get("status")
            if identifier not in specs:
                issues.append(role + ": unknown case " + str(identifier)); continue
            if status != "skipped" and (selection["kind"] not in specs[identifier]["kinds"] or selection["mode"] not in specs[identifier].get("modes", ("toolkit", "native"))):
                issues.append(role + ": unsupported case kind/mode " + identifier)
            if status not in ("passed", "failed", "skipped"):
                issues.append(role + ": invalid status " + str(status)); continue
            if status == "skipped" and not event.get("reason"):
                issues.append(role + ": skip without reason")
            counts[status] += 1
            if status == "passed":
                if selection['suite'] == 'health' and identifier in HEALTH_COMPLETION_CASES:
                    outcome = event.get('outcome')
                    phases = outcome.get('nativeCompletion') if isinstance(outcome, dict) else None
                    count = 1 if selection['mode'] == 'toolkit' else 0
                    expected = dict(perform=count, complete=count if selection['kind'] == 'sp' else 0, flush=count)
                    if (not isinstance(phases, dict) or set(phases) != set(expected)
                            or any(type(phases.get(key)) is not int or phases[key] != value for key, value in expected.items())):
                        issues.append(role + ': native medical completion phases differ ' + identifier)
                matches = [r for r in receipts if r[1] == identifier and (selection["kind"] == "sp" or r[0] == role)]
                expected_patient = role if specs[identifier]["producer"] == "inventory" else "client2" if role == "client1" else "client1"
                if len(matches) != 1 or matches[0][2] != "true" or matches[0][4] != "nil" or (selection["kind"] == "mp" and matches[0][3] != expected_patient) or (selection["kind"] == "sp" and matches[0][0] != matches[0][3]):
                    issues.append(role + ": missing/duplicate/failed authority receipt " + identifier)
            coverage.append({"suite": selection["suite"], "case": identifier, "producer": specs[identifier]["producer"],
                             "capability": specs[identifier]["capability"], "kind": selection["kind"], "mode": selection["mode"],
                             "actor": role, "status": status, "reason": event.get("reason"), "outcome": event.get("outcome")})
        if complete:
            end = complete[0]
            expected_counts = {"expected": len(selection["cases"]), "performed": counts["passed"] + counts["failed"], "skipped": counts["skipped"], "failed": counts["failed"]}
            if end.get("cases") != selection["cases"] or any(type(end.get(key)) is not int or end[key] != value for key, value in expected_counts.items()):
                issues.append(role + ": completion counters differ from actual case events")
        if counts["failed"]:
            issues.append(role + ": failed scenarios")
        clients[role] = dict(counts)
    return {"status": "failed" if issues else "passed", "issues": issues, "clients": clients}, coverage


def compare(current, control):
    reasons = []
    if current["selection"]["mode"] != "toolkit" or control["selection"]["mode"] != "native":
        reasons.append("Comparison requires toolkit run and native control")
    if current.get("settings_fingerprint") != control.get("settings_fingerprint") or not current.get("settings_fingerprint"):
        reasons.append("Game, source, mods, cases or settings differ")
    for label, report in (("toolkit", current), ("control", control)):
        if report["functional"]["status"] != "passed" or not report["provenance"]["verified"] or execution_issues(report.get('run'), report['selection'], report.get('execution')):
            reasons.append(label + " run lacks verified functional completion")
        expected_roles = set(adapters.roles(report['selection']))
        if set(report["runtime"]["roles"]) != expected_roles or report["runtime"]["microphone"] or any(not audit.get("available") for audit in report["runtime"]["roles"].values()):
            reasons.append(label + " run lacks safe, available runtime logs")
    def executed(report):
        return [(row["actor"], row["case"], row["status"]) for row in report["coverage"]]
    if executed(current) != executed(control):
        reasons.append("Executed/skipped scenarios differ; error causality cannot be compared")
    differences, outcomes = {}, []
    if not reasons:
        for role, audit in current["runtime"]["roles"].items():
            before = Counter({row["fingerprint"]: row["count"] for row in control["runtime"]["roles"].get(role, {}).get("issues", [])})
            after = Counter({row["fingerprint"]: row["count"] for row in audit["issues"]})
            differences[role] = {"only_toolkit": dict(after - before), "only_control": dict(before - after), "shared": dict(after & before)}
        for after, before in zip(current["coverage"], control["coverage"]):
            outcomes.append({"actor": after["actor"], "case": after["case"], "toolkit": after.get("outcome"), "native": before.get("outcome"), "equal": after.get("outcome") == before.get("outcome")})
    return {"compatible": not reasons, "reasons": reasons, "errors": differences, "outcomes": outcomes,
            "interpretation": "Matching errors reproduce without queue; comparison never clears failures or unclassified errors."}


def execution_issues(root, selection, execution):
    if not isinstance(root, (str, Path)) or not Path(root).is_absolute():
        return ['Execution requires an absolute owned run path']
    root = Path(root)
    if not isinstance(execution, dict):
        return ['Execution record is missing or invalid']
    issues = [] if execution.get('status') == 'completed' else ['Execution is not completed']
    processes = execution.get('processes')
    roles = adapters.roles(selection)
    if not isinstance(processes, dict) or set(processes) != set(roles):
        return issues + ['Execution requires process records for exactly the selected roles']
    hosted = selection['kind'] == 'mp' and selection.get('options', {}).get('mp_host') is True
    for role, process in processes.items():
        if not isinstance(process, dict) or type(process.get('pid')) is not int or process['pid'] <= 0:
            issues.append(role + ': execution requires a positive integer PID')
            continue
        if hosted and role == 'server':
            if process.get('parent_role') != 'client1' or process.get('cache') != str(root / 'client1'):
                issues.append('server: Host execution requires the owned client1 parent/cache')
        elif type(process.get('exit_code')) is not int:
            issues.append(role + ': execution requires an integer exit code after stopping')
        elif execution.get('platform') != 'win32' and process['exit_code'] not in (0, -15, -9, 143, 137):
            # macOS JVMs may return 128+signal for the runner's TERM/KILL cleanup.
            issues.append(role + ': unexpected process exit code ' + str(process['exit_code']))
    if hosted:
        cleanup = execution.get('host_cleanup')
        if not isinstance(cleanup, dict) or cleanup.get('remaining_pids') != []:
            issues.append('Host execution requires a completed cleanup audit with no remaining PIDs')
    return issues


def _optimizer_viewports(root, role, text, expected, actuals, required, native_benchmark=False):
    """Admit the exact selected Display contract using fresh owned-window measurements."""
    contract = 'logical' if native_benchmark else 'framebuffer'
    display_sha256 = ('15a0c0a3646d4340cd96c47d143a5605bfbae7543410ddaa018e83f45ae1a578'
                      if native_benchmark else 'da78691b554a0341827f841abc73a34b776ecf0fde845b15703cb855a8847d57')
    pattern = (r'\[QUEUE_TEST\] WINDOW_VIEWPORT pid=(\d+) glfw=(\d+) contract=(\w+) '
               r'display_sha256=([0-9a-f]{64}) window=(\d+)x(\d+) framebuffer=(\d+)x(\d+) '
               r'display=(\d+)x(\d+) core=(\d+)x(\d+)(?:\s|$)')
    matches = re.findall(pattern, text)
    if len(matches) != required or text.count('[QUEUE_TEST] WINDOW_VIEWPORT ') != required:
        raise ValueError('exact optimizer viewport observations missing or duplicated')
    routes = {(int(pid), int(handle)) for pid, handle in re.findall(
        r'\[QUEUE_TEST\] WINDOW_ROUTED pid=(\d+) glfw=(\d+) mode=', text)}
    execution = read_json(Path(root) / 'execution.json')
    pid = execution['processes'][role]['pid']
    if type(pid) is not int or pid <= 0:
        raise ValueError('owned process identity is missing')
    result = []
    for row, actual in zip(matches, actuals):
        owner, handle = map(int, row[:2])
        values = list(map(int, row[4:]))
        logical, framebuffer, display, core = (values[i:i+2] for i in range(0, 8, 2))
        if (owner != pid or handle <= 0 or (owner, handle) not in routes
                or row[2] != contract
                or row[3] != display_sha256
                or min(values) <= 0 or logical != expected or core != actual
                or core != (logical if native_benchmark else framebuffer)
                or display != (logical if native_benchmark else framebuffer)):
            raise ValueError('optimizer viewport does not match its owned window/' + contract + ' contract')
        result.append({'logical': logical, 'framebuffer': framebuffer, 'display': display, 'core': core,
                       'pid': owner, 'glfw': handle, 'contract': row[2], 'display_sha256': row[3]})
    return result


def window_size_evidence(root, selection):
    """Require the declared number of native starts, each at the prepared viewport."""
    expected = selection.get('window_size')
    evidence = {'expected': expected, 'observed': {}, 'issues': []}
    if expected is None:  # Legacy snapshots did not declare a viewport contract.
        return evidence
    roles = adapters.roles(selection, False)
    adapter = adapters.get(selection.get('suite'))
    declare = getattr(adapter, 'window_start_counts', None)
    counts = declare(selection) if declare else {}
    if (not isinstance(counts, dict) or any(role not in roles or type(count) is not int or count < 1
                                           for role, count in counts.items())):
        evidence['issues'].append('Invalid adapter window_start_counts declaration')
        return evidence
    if counts:
        evidence['startup_observations'] = {}
    if selection.get('suite') == 'optimizer-benchmark' and selection.get('options', {}).get('optimizer_archive'):
        evidence['limits'] = ['Accepted individual viewport contracts do not establish a performance comparison. Native/optimized runs with differing measured logical, framebuffer, Display or Core pixel dimensions cannot be accepted as a performance comparison.']
    for role in roles:
        path = Path(root) / (role + '-launch.log')
        text = path.read_text(errors='replace') if path.is_file() else ''
        sizes = re.findall(r'\[QUEUE_TEST\] WINDOW_SIZE width=(\d+) height=(\d+)(?:\s|$)', text)
        actuals = [list(map(int, size)) for size in sizes]
        if counts:
            evidence['startup_observations'][role] = actuals
        required = counts.get(role, 1)
        if len(actuals) != required:
            label = 'one startup observation' if required == 1 else str(required) + ' startup observations'
            evidence['issues'].append(role + ': window_size requires exactly ' + label)
            continue
        evidence['observed'][role] = actuals[0]
        if selection.get('options', {}).get('optimizer_archive'):
            try:
                native_benchmark = (selection.get('suite') == 'optimizer-benchmark'
                                    and selection.get('options', {}).get('optimizer_enabled') is False)
                observed = _optimizer_viewports(root, role, text, expected, actuals, required, native_benchmark)
                evidence.setdefault('geometry', {})[role] = observed
            except (OSError, ValueError, KeyError, TypeError) as error:
                evidence['issues'].append(role + ': ' + str(error))
            continue
        for index, actual in enumerate(actuals):
            if actual != expected:
                position = ' at startup ' + str(index + 1) if required > 1 else ''
                evidence['issues'].append(role + ': window_size differs from prepared viewport' + position + ': ' + str(actual))
    return evidence


def build_report(root, catalog, control=None):
    root = Path(root).resolve()
    selection = read_json(root / "selection.json")
    provenance_errors = verify_manifest(root, "source-manifest.json", absolute=True) + verify_manifest(root, "snapshot-hashes.json")
    result, coverage = functional(root, selection, catalog)
    roles = adapters.roles(selection)
    audits = audit_logs(root, roles, background_profile(root, selection, not provenance_errors),
                        verified_game_sha256(root, not provenance_errors),
                        selection.get('options', {}).get('mp_host') is True)
    try:
        execution = read_json(root / "execution.json")
    except (OSError, ValueError):
        execution = {"status": "missing"}
    if not isinstance(execution, dict):
        execution = {"status": "invalid"}
    execution_errors = execution_issues(root, selection, execution)
    viewport = window_size_evidence(root, selection)
    execution_errors += viewport['issues']
    microphone = any(row["microphone"] for row in audits.values())
    counts = {severity + "_count": sum(row[severity + "_count"] for row in audits.values())
              for severity in ("fatal", "unclassified", "background")}
    runtime_status = "failed" if counts["fatal_count"] else "unclassified-errors" if counts["unclassified_count"] else "background-only" if counts["background_count"] else "clean"
    fingerprint = read_json(root / "settings-fingerprint.json")["sha256"]
    report = {"schema_version": 1, "run": str(root), "selection": selection,
              "settings_fingerprint": fingerprint, "provenance": {"verified": not provenance_errors, "issues": provenance_errors,
                  'game_input_trees': list(GAME_INPUT_TREES) if not provenance_errors else []},
              "functional": result, "coverage": coverage, "execution": execution, "execution_issues": execution_errors, "window_size": viewport,
              "runtime": dict(counts, status="unavailable" if any(not row["available"] for row in audits.values()) else runtime_status, roles=audits, microphone=microphone),
              "limits": ["Callback-driven native fixture; physical UI, WAN and long sessions are separate coverage.",
                         "Native tree seal scope: media/lua and media/scripts; other asset/binary trees are outside this seal."]}
    if control is not None:
        report["comparison"] = compare(report, control)
        if report["comparison"]["compatible"] and not counts["fatal_count"] and counts["unclassified_count"]:
            new = any(issue["severity"] == "unclassified" and issue["fingerprint"] in report["comparison"]["errors"][role]["only_toolkit"]
                      for role, audit in audits.items() for issue in audit["issues"])
            report["runtime"]["status"] = "new-errors" if new else "unclassified-errors"
    failed = counts["fatal_count"] or result["status"] not in ('passed', 'captured') or provenance_errors or microphone or execution_errors or any(not row["available"] for row in audits.values())
    if failed:
        report["status"] = "failed"
    elif control is not None and not report["comparison"]["compatible"]:
        report["status"] = "needs-review"
    elif result['status'] == 'captured' or (result.get('evidence') or {}).get('requires_review') or report["runtime"]["status"] in ("unclassified-errors", "new-errors"):
        report["status"] = "needs-review"
    else:
        report["status"] = "passed"
    return report


def _case_matrix(catalog, reports=()):
    rows = []
    for suite, definition in catalog["suites"].items():
        if not definition["cases"]:
            rows.append({"suite": suite, "status": definition["status"], "case": None})
        for case in definition["cases"]:
            for kind in case["kinds"]:
                for mode in ("toolkit", "native"):
                    if mode not in case.get("modes", ("toolkit", "native")):
                        rows.append({"suite": suite, "case": case["id"], "producer": case["producer"], "capability": case["capability"], "kind": kind, "mode": mode, "status": "unsupported", "reason": case.get('control_reason', "Requires toolkit queue API")})
                        continue
                    expected_actors = {'client' + str(i+1) for i in range(1 if kind == 'sp' else case.get('clients', definition.get('clients', 2)))}
                    relevant = [(report, [row for row in report["coverage"] if row["suite"] == suite and row["case"] == case["id"] and row["kind"] == kind and row["mode"] == mode]) for report in reports]
                    relevant = [(report, matches) for report, matches in relevant if matches]
                    full = [(report, matches) for report, matches in relevant
                            if not any((row.get('outcome') or {}).get('partialCoverage') is True for row in matches)]
                    if full:
                        relevant = full
                    matches = [row for _, values in relevant for row in values]
                    invalid = any(report.get("status") == "failed" or report["functional"]["status"] not in ('passed', 'captured') or not report["provenance"]["verified"] or execution_issues(report.get('run'), report['selection'], report.get('execution')) for report, _ in relevant)
                    incomplete = any({row["actor"] for row in values} != expected_actors or len(values) != len(expected_actors)
                                     or any((row.get('outcome') or {}).get('partialCoverage') is True for row in values)
                                     for _, values in relevant)
                    rows.append({"suite": suite, "case": case["id"], "producer": case["producer"], "capability": case["capability"],
                                 "kind": kind, "mode": mode, "status": "not-run" if not matches else "failed" if invalid or any(row["status"] == "failed" for row in matches) else "partial" if incomplete else "skipped" if all(row["status"] == "skipped" for row in matches) else "partial" if any(row["status"] == "skipped" for row in matches) else "passed",
                                 "evidence": matches})
                    if matches and not invalid and not incomplete and all(row['status'] == 'captured' for row in matches):
                        rows[-1]['status'] = 'captured'
    return {"schema_version": 1, "rows": rows}


def matrix(catalog, reports=()):
    from . import scenarios
    value = _case_matrix(catalog, reports)
    value['scenarios'] = scenarios.matrix(catalog, reports, _case_matrix)
    return value


def summary(report):
    lines = ["Overall: " + report["status"], "Execution: " + str(report["execution"].get("status", "invalid")), "Functional: " + report["functional"]["status"], "Runtime: " + report["runtime"]["status"],
             "Sources/snapshot: " + ("verified" if report["provenance"]["verified"] else "CHANGED")]
    viewport = report.get('window_size', {})
    if viewport.get('expected'):
        lines.append('Window size: expected ' + 'x'.join(map(str, viewport['expected'])) + '; observed ' +
                     ', '.join(role + '=' + 'x'.join(map(str, size)) for role, size in viewport.get('observed', {}).items()))
        for role, observations in viewport.get('geometry', {}).items():
            for value in observations:
                lines.append(role + ' measured logical=' + 'x'.join(map(str, value['logical']))
                             + '; framebuffer=' + 'x'.join(map(str, value['framebuffer']))
                             + '; game=' + 'x'.join(map(str, value['core'])))
    trees = report['provenance'].get('game_input_trees')
    lines.append('Live game trees: ' + ('unsealed (legacy report)' if trees is None else ', '.join(trees) if trees else 'NOT VERIFIED'))
    for role, counts in report["functional"]["clients"].items():
        lines.append(role + ": " + ", ".join(str(counts.get(status, 0)) + " " + status for status in ("passed", "skipped", "failed", 'captured') if status != 'captured' or counts.get(status)))
    for role, audit in report["runtime"]["roles"].items():
        lines.append(role + ": " + str(audit["error_count"]) + " errors, " +
                     ", ".join(str(audit.get(severity + "_count", 0)) + " " + severity for severity in ("fatal", "unclassified", "background")) +
                     ", " + str(len(audit["microphone"])) + " microphone markers")
        if windows := audit.get('diagnostic_windows'):
            lines.append(role + ' diagnostic errors: startup=' + str(windows['startup']['error_count']) +
                         ', between-cases=' + str(windows['between_cases']['error_count']) + ', unassigned=' + str(windows['unassigned']['error_count']))
            for case in windows['cases']:
                lines.append(role + ' ' + case['case'] + ' epoch=' + str(case['epoch']) + ' diagnostic errors: run=' +
                             str(case['run']['error_count']) + ', cleanup=' + str(case['cleanup']['error_count']))
    lines.extend(report["functional"]["issues"] + report["provenance"]["issues"] + report.get('execution_issues', []))
    if report["execution"].get("error"):
        lines.append(report["execution"]["error"])
    if "comparison" in report:
        lines.extend(report["comparison"]["reasons"])
    return "\n".join(lines) + "\n"
