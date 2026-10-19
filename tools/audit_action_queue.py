#!/usr/bin/env python3
"""Read-only timed-action census and runtime presentation-registry validation.

Behavior declarations and passing fixtures are separate evidence: this tool never
asserts that a declared adapter passed a native fixture or an SP/MP game scenario.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

try:
    from .queue_checks.mod_selection import (
        VERSION, local_mod_infos, matching_roots, metadata, mod_ids, mod_info, mod_layers,
    )
except ImportError:
    from queue_checks.mod_selection import (
        VERSION, local_mod_infos, matching_roots, metadata, mod_ids, mod_info, mod_layers,
    )

ROOT = Path(__file__).resolve().parent.parent
DERIVE = re.compile(r"([\w.]+)\s*=\s*([\w.]+)\s*:\s*derive\s*\(\s*['\"]([^'\"]+)['\"]")


def read(path):
    return path.read_text(encoding="utf-8-sig", errors="replace")


def source_roots(project, native, workshop, ini, version):
    roots, mods = [], []
    if native and native.is_dir():
        roots.append(("native", native))
    settings = metadata(ini) if ini else {}
    selected_value = settings.get("Mods", "PZSurvivorToolkit")
    selected = [] if selected_value == "" else mod_ids(selected_value)
    ids = [x for x in settings.get("WorkshopItems", "").split(";") if x]
    local_infos = local_mod_infos(project)
    workshop_infos = [info for wid in ids for info in (workshop / wid).glob("mods/**/mod.info")] if workshop else []
    for mod in selected:
        folders = matching_roots(local_infos, mod) or matching_roots(workshop_infos, mod)
        if len(folders) != 1:
            mods.append({"id": mod, "status": "missing-or-ambiguous", "roots": sorted(map(str, folders))})
            continue
        folder = next(iter(folders))
        layers = mod_layers(folder, version)
        active_info = mod_info(folder, version)
        actual_id = metadata(active_info).get("id") if active_info else None
        if layers and actual_id != mod:
            mods.append({"id": mod, "status": "different-mod-id", "root": str(folder),
                         "actual_id": actual_id})
            continue
        roots.extend((mod, layer / "media/lua") for layer in layers)
        mods.append({"id": mod, "status": "found" if layers else "missing-compatible-version",
                     "layers": [str(layer) for layer in layers]})
    return roots, mods


def census(roots):
    # A selected version replaces common files only within the same mod.
    sources = {}
    for origin, root in roots:
        for path in root.rglob("*.lua"):
            sources[(origin, str(path.relative_to(root)))] = path
    definitions = []
    for (origin, relative), path in sources.items():
        text = read(path)
        for match in DERIVE.finditer(text):
            if text[text.rfind("\n", 0, match.start()) + 1:match.start()].lstrip().startswith("--"):
                continue
            definitions.append({"class": match[1], "parent": match[2], "type": match[3], "origin": origin,
                                "relative": relative, "source": str(path), "line": text.count("\n", 0, match.start()) + 1,
                                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    actions = {"ISBaseTimedAction"}
    while True:
        expanded = actions | {row["class"] for row in definitions if row["parent"] in actions}
        if expanded == actions:
            break
        actions = expanded
    return [row for row in definitions if row["class"] in actions and row["class"] != "ISBaseTimedAction"]


def translations(project, native):
    values = {}
    for language in ("EN", "RU"):
        data = {}
        if native and native.is_dir():
            for path in (native / "shared/Translate" / language).glob("*.json"):
                data.update(json.loads(read(path)))
        data.update(json.loads(read(project / "PZSurvivorToolkit/42/media/lua/shared/Translate" / language / "UI.json")))
        values[language] = data
    return values


def registry(project):
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as error:
        raise RuntimeError("Install the development test dependency lupa to inspect runtime Definitions") from error
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("PZSurvivorToolkit = {}")
    path = project / "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua"
    definitions = lua.execute(read(path))  # Duplicate/conflicting registration assertions run here.
    return {kind: {"id": identifier, "key": definitions.entries[identifier].presentation.key,
                   "mode_keys": list((definitions.entries[identifier].presentation.modes or {}).values()),
                   "family": definitions.entries[identifier].presentation.family,
                   "role": definitions.entries[identifier].presentation.role}
            for kind, identifier in definitions.types.items()}


def declared_behavior(project):
    names = set()
    folder = project / "PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit"
    for path in folder.glob("ActionQueue*.lua"):
        if path.name == "ActionQueueDefinitions.lua":
            continue
        text = read(path)
        names.update(re.findall(r"registerNative\(\s*[\"']([^\"']+)", text))
        for body in re.findall(r"types\s*=\s*\{([^}]*)\}", text):
            names.update(re.findall(r"[\"']([^\"']+)", body))
        for body in re.findall(r"for\s+_,\s*name\s+in\s+ipairs\(\{([^}]*)\}\)\s+do\s+registerNative\(name", text):
            names.update(re.findall(r"[\"']([^\"']+)", body))
    return names


def audit(project=ROOT, native=None, workshop=None, ini=None, version=(42, 21)):
    roots, mods = source_roots(project, native, workshop, ini, version)
    actions, presentations = census(roots), registry(project)
    values, behavior = translations(project, native), declared_behavior(project)
    errors, unavailable = [], []
    own = {lang: json.loads(read(project / "PZSurvivorToolkit/42/media/lua/shared/Translate" / lang / "UI.json")) for lang in ("EN", "RU")}
    if set(own["EN"]) != set(own["RU"]):
        errors.append("EN/RU Toolkit keys differ")
    for key in own["EN"].keys() & own["RU"].keys():
        if sorted(re.findall(r"%\d+", own["EN"][key])) != sorted(re.findall(r"%\d+", own["RU"][key])):
            errors.append("EN/RU placeholders differ: " + key)
    for kind, descriptor in presentations.items():
        for key in [descriptor["key"], *descriptor["mode_keys"]]:
            if not key:
                errors.append("Presentation without title key: " + kind)
                continue
            for language in ("EN", "RU"):
                if key not in values[language]:
                    (errors if native and native.is_dir() or key.startswith("UI_PZSurvivorToolkit_") else unavailable).append(language + ": missing " + key)
                elif re.search(r"%\d+", values[language][key]):
                    errors.append(language + ": title needs unprovided arguments: " + key)
    for row in actions:
        row.update({"detected": True, "presentation": presentations.get(row["type"]),
                    "behavior": "source-declaration" if row["type"] in behavior else "none-or-unrecognized",
                    "native_fixture": "not-run", "game_sp": "not-run", "game_mp": "not-run"})
        if row["type"] not in presentations:
            row["presentation_fallback"] = "safe Type fallback; behavior remains closed; presentation review required"
            if row["origin"] == "native":
                errors.append("Native action missing explicit presentation: " + row["type"])
    return {"native_status": "FOUND" if native and native.is_dir() else "SKIP: installed game sources not supplied or unavailable",
            "actions": actions, "mods": mods, "registry_types": len(presentations),
            "errors": sorted(set(errors)), "native_translation_checks_skipped": sorted(set(unavailable)),
            "evidence": "Source census and runtime presentation registry only; behavior declarations do not prove safe execution."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--native-root", type=Path, help="installed game media/lua directory")
    parser.add_argument("--workshop-root", type=Path, help="Steam Workshop content/108600 directory")
    parser.add_argument("--selected-ini", type=Path, help="server INI selecting Mods and WorkshopItems")
    parser.add_argument("--game-version", default="42.21", help="highest compatible version layer")
    parser.add_argument("--output", type=Path, help="write JSON catalog; default prints it")
    parser.add_argument("--require-native", action="store_true", help="treat missing native sources as an unfinished release gate")
    args = parser.parse_args()
    if not VERSION.fullmatch(args.game_version):
        parser.error("--game-version must be numeric, e.g. 42.21")
    try:
        result = audit(args.project_root, args.native_root, args.workshop_root, args.selected_ini,
                       tuple(map(int, args.game_version.split("."))))
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1, str(error) + "\n")
    output = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
        print(json.dumps({"catalog": str(args.output), "actions": len(result["actions"]),
                          "native_status": result["native_status"], "errors": result["errors"]}))
    else:
        print(output, end="")
    return 1 if result["errors"] or args.require_native and result["native_status"].startswith("SKIP") else 0


if __name__ == "__main__":
    raise SystemExit(main())
