"""Exact scenario results, bounded log auditing and comparable native controls."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import re


MARKER = "[QUEUE_CHECK] "
RECORD = re.compile(r"^(?:LOG|WARN|ERROR|DEBUG|TRACE)\s*:")
STAMP = re.compile(r"^\[\d{2}-\d{2}-\d{2,4}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?\]\s*")
MIC = ("System create record sound", "initialisedRecDev=true", "fmodRecordSound=", "Microphone was not disabled")
RECEIPT = re.compile(r"HEALTH_AUTH_RECEIPT (\S*) phase=(\w+) ok=(true|false) patient=(\S*) error=([^\n]+)")


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


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
    if filename == "snapshot-hashes.json" and not absolute:
        required = {"selection.json", "runtime.json", "settings-fingerprint.json", "source-manifest.json", "manifest.json", "initial-settings.json"}
        missing = required - manifest.keys()
        if missing:
            errors.append("Snapshot metadata missing: " + ", ".join(sorted(missing)))
        try:
            selection = read_json(root / "selection.json")
            roles = ["client1"] if selection["kind"] == "sp" else ["server", "client1", "client2"]
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
    paths = [root / (role + "-launch.log"), root / role / "console.txt"]
    paths += sorted((root / role / "Logs").glob("*DebugLog*.txt"))
    return [path for path in paths if path.is_file()]


def audit_log(path, cache):
    """Keep counts within a file; mirrors are merged using max, never summed."""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    findings, microphone = [], []
    for number, line in enumerate(lines, 1):
        for marker in MIC:
            if marker in line and not (marker == "fmodRecordSound=" and re.search(r"fmodRecordSound=0(?:\s|$|[,;}])", line)):
                microphone.append({"file": str(path), "line": number, "message": line})
    lines = [STAMP.sub("", line) for line in lines]
    starts = [i for i, line in enumerate(lines) if RECORD.match(line)]
    if lines and (not starts or starts[0] != 0):
        starts.insert(0, 0)
    for index, start in enumerate(starts):
        block = lines[start:starts[index + 1] if index + 1 < len(starts) else len(lines)]
        is_error = re.match(r"^ERROR\s*:", block[0]) or re.search(r"(?:KahluaException|\b[\w.]+(?:Exception|Error):)", "\n".join(block))
        if not is_error:
            continue
        message = block[0].split(">", 1)[-1].strip()
        cause = next((line.strip() for line in block[1:] if re.search(r"(?:Exception|Error)(?::|\b)", line)), "")
        message = message.replace(str(cache), "<cache>")
        cause = cause.replace(str(cache), "<cache>")
        # DebugLog's formatter can append a second full stop to a mirrored console message.
        key = message.rstrip(".") + ("\n" + cause.rstrip(".") if cause else "")
        findings.append({"fingerprint": hashlib.sha256(key.encode()).hexdigest(), "message": message,
                         "cause": cause, "file": str(path), "line": start + 1,
                         "category": "lua" if "Kahlua" in key or "Lua(" in key else "native"})
    return findings, microphone


def audit_logs(root, roles):
    result = {}
    for role in roles:
        merged, details, microphone = Counter(), {}, []
        paths = log_paths(root, role)
        for path in paths:
            findings, mic = audit_log(path, root / role)
            current = Counter(row["fingerprint"] for row in findings)
            merged |= current
            details.update({row["fingerprint"]: row for row in findings})
            microphone.extend(mic)
        result[role] = {"files": list(map(str, paths)), "issues": [dict(details[key], count=count) for key, count in sorted(merged.items())],
                        "error_count": sum(merged.values()), "microphone": microphone,
                        "available": bool(paths) and any(path.stat().st_size for path in paths)}
    return result


def functional(root, selection, catalog):
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
                matches = [r for r in receipts if r[1] == identifier and (selection["kind"] == "sp" or r[0] == role)]
                expected_patient = "client2" if role == "client1" else "client1"
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
        if report["functional"]["status"] != "passed" or not report["provenance"]["verified"] or report.get("execution", {}).get("status") != "completed":
            reasons.append(label + " run lacks verified functional completion")
        expected_roles = {"client1"} if report["selection"]["kind"] == "sp" else {"server", "client1", "client2"}
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
            "interpretation": "Matching errors reproduce without queue; differences require investigation, not automatic attribution."}


def build_report(root, catalog, control=None):
    root = Path(root).resolve()
    selection = read_json(root / "selection.json")
    provenance_errors = verify_manifest(root, "source-manifest.json", absolute=True) + verify_manifest(root, "snapshot-hashes.json")
    result, coverage = functional(root, selection, catalog)
    roles = ["client1"] if selection["kind"] == "sp" else ["server", "client1", "client2"]
    audits = audit_logs(root, roles)
    try:
        execution = read_json(root / "execution.json")
    except (OSError, ValueError):
        execution = {"status": "missing"}
    if not isinstance(execution, dict):
        execution = {"status": "invalid"}
    microphone = any(row["microphone"] for row in audits.values())
    total = sum(row["error_count"] for row in audits.values())
    fingerprint = read_json(root / "settings-fingerprint.json")["sha256"]
    report = {"schema_version": 1, "run": str(root), "selection": selection,
              "settings_fingerprint": fingerprint, "provenance": {"verified": not provenance_errors, "issues": provenance_errors},
              "functional": result, "coverage": coverage, "execution": execution,
              "runtime": {"status": "unavailable" if any(not row["available"] for row in audits.values()) else "unclassified-errors" if total else "clean", "roles": audits, "microphone": microphone},
              "limits": ["Callback-driven native fixture; physical UI, WAN and long sessions are separate coverage."]}
    if control is not None:
        report["comparison"] = compare(report, control)
        if report["comparison"]["compatible"]:
            new = any(row["only_toolkit"] for row in report["comparison"]["errors"].values())
            report["runtime"]["status"] = "new-errors" if new else "reproduced-without-queue" if total else "clean"
    failed = result["status"] != "passed" or provenance_errors or microphone or execution.get("status") != "completed" or any(not row["available"] for row in audits.values())
    if failed:
        report["status"] = "failed"
    elif control is not None and not report["comparison"]["compatible"]:
        report["status"] = "needs-review"
    elif report["runtime"]["status"] in ("unclassified-errors", "new-errors"):
        report["status"] = "needs-review"
    else:
        report["status"] = "passed"
    return report


def matrix(catalog, reports=()):
    rows = []
    for suite, definition in catalog["suites"].items():
        if not definition["cases"]:
            rows.append({"suite": suite, "status": definition["status"], "case": None})
        for case in definition["cases"]:
            for kind in case["kinds"]:
                for mode in ("toolkit", "native"):
                    if mode not in case.get("modes", ("toolkit", "native")):
                        rows.append({"suite": suite, "case": case["id"], "producer": case["producer"], "capability": case["capability"], "kind": kind, "mode": mode, "status": "unsupported", "reason": "Requires toolkit queue API"})
                        continue
                    expected_actors = {"client1"} if kind == "sp" else {"client1", "client2"}
                    relevant = [(report, [row for row in report["coverage"] if row["suite"] == suite and row["case"] == case["id"] and row["kind"] == kind and row["mode"] == mode]) for report in reports]
                    relevant = [(report, matches) for report, matches in relevant if matches]
                    matches = [row for _, values in relevant for row in values]
                    invalid = any(report.get("status") == "failed" or report["functional"]["status"] != "passed" or not report["provenance"]["verified"] or report.get("execution", {}).get("status") != "completed" for report, _ in relevant)
                    incomplete = any({row["actor"] for row in values} != expected_actors or len(values) != len(expected_actors) for _, values in relevant)
                    rows.append({"suite": suite, "case": case["id"], "producer": case["producer"], "capability": case["capability"],
                                 "kind": kind, "mode": mode, "status": "not-run" if not matches else "failed" if invalid or any(row["status"] == "failed" for row in matches) else "partial" if incomplete else "skipped" if all(row["status"] == "skipped" for row in matches) else "partial" if any(row["status"] == "skipped" for row in matches) else "passed",
                                 "evidence": matches})
    return {"schema_version": 1, "rows": rows}


def summary(report):
    lines = ["Overall: " + report["status"], "Execution: " + report["execution"]["status"], "Functional: " + report["functional"]["status"], "Runtime: " + report["runtime"]["status"],
             "Sources/snapshot: " + ("verified" if report["provenance"]["verified"] else "CHANGED")]
    for role, counts in report["functional"]["clients"].items():
        lines.append(role + ": " + ", ".join(str(counts.get(status, 0)) + " " + status for status in ("passed", "skipped", "failed")))
    for role, audit in report["runtime"]["roles"].items():
        lines.append(role + ": " + str(audit["error_count"]) + " errors, " + str(len(audit["microphone"])) + " microphone markers")
    lines.extend(report["functional"]["issues"] + report["provenance"]["issues"])
    if report["execution"].get("error"):
        lines.append(report["execution"]["error"])
    if "comparison" in report:
        lines.extend(report["comparison"]["reasons"])
    return "\n".join(lines) + "\n"
