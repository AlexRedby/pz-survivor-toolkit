#!/usr/bin/env python3
"""Compare DisplayCategory coverage and the reviewed organizedCategories source identity."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

EN_TRANSLATION = "shared/Translate/EN/IG_UI.json"
OC_BASELINE = Path(__file__).with_name("organized_categories_baseline.json")


def taxonomy_fingerprints(lua_root):
    files = [lua_root / EN_TRANSLATION]
    # Conservatively include readers/helpers too: dynamic writers need more than literal-ID checks.
    files.extend(path for path in source_files(lua_root, {".lua"})
                 if any(marker in path.read_bytes() for marker in (b"DisplayCategory", b"TweakItem")))
    return {path.relative_to(lua_root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(files)}


def load_baseline(path):
    baseline = json.loads(path.read_text())
    if not isinstance(baseline, dict) or baseline.get("format") != 1:
        raise ValueError(f"invalid organizedCategories baseline format: {path}")
    files = baseline.get("files")
    digest = baseline.get("schema_sha256")
    valid_digest = lambda value: isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value)
    if (not isinstance(files, dict) or EN_TRANSLATION not in files or not valid_digest(digest)
            or any(not isinstance(name, str) or Path(name).is_absolute() or ".." in Path(name).parts
                   or "\\" in name or name != Path(name).as_posix()
                   or (not name.endswith(".lua") and name != EN_TRANSLATION)
                   or not valid_digest(value) for name, value in files.items())):
        raise ValueError(f"invalid organizedCategories baseline hashes: {path}")
    return baseline


def baseline_changes(expected, current):
    changes = []
    for name in sorted(expected.keys() | current.keys()):
        if name not in expected:
            changes.append(f"added source: {name}")
        elif name not in current:
            changes.append(f"removed source: {name}")
        elif expected[name] != current[name]:
            changes.append(f"changed source: {name}")
    return changes


def lua_roots(path):
    versioned = path / "42" / "media" / "lua"
    if versioned.is_dir():
        return [versioned]
    if path.name == "lua" and path.parent.name == "media" and path.parent.parent.name == "42":
        return [path]
    raise ValueError(f"{path} is not an organizedCategories root or 42/media/lua directory")


def organized_categories_source_root(path):
    if (path / "42").is_dir():
        return path
    return next((parent for parent in path.parents if (parent / "42" / "media" / "lua").is_dir()), None)


def source_files(root, suffixes):
    if not root:
        return []
    return [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in suffixes]


def category_keys(schema):
    match = re.search(r"categories\s*=\s*\{(.*?)\}\s*,?\s*labels\s*=\s*\{", schema, re.S)
    if not match:
        return set()
    body = match.group(1)
    return set(re.findall(r'^\s*\["([^"]+)"\]\s*=\s*\{', body, re.M))


def uncovered(values, known):
    return values - known


def require_directory(path, option):
    if not path.is_dir():
        raise ValueError(f"{option} must point to an existing directory: {path}")


def require_sources(root, suffixes, option):
    files = source_files(root, suffixes)
    if not files:
        raise ValueError(f"{option} contains no supported source files: {root}")
    return files


def game_scripts_root(path):
    require_directory(path, "--game")
    scripts = path / "media" / "scripts"
    if scripts.is_dir():
        return scripts
    if path.name == "scripts":
        return path
    raise ValueError("--game must be a game root containing media/scripts or the media/scripts directory")


def inspect_lua(path):
    text = path.read_text(errors="replace")
    text = re.sub(r'--\[(=*)\[.*?\]\1\]', "", text, flags=re.S)
    text = re.sub(r'--[^\n]*', "", text)
    constants = dict(re.findall(r'\b(?:local\s+)?(\w+)\s*=\s*["\']([^"\']+)["\']', text))
    values, dynamic = set(), set()
    calls = r'TweakItem\(\s*"[^"]*"\s*,\s*"DisplayCategory"\s*,\s*("([^"]+)"|\'([^\']+)\'|(\w+))'
    setters = r'\bsetDisplayCategory\(\s*("([^"]+)"|\'([^\']+)\'|(\w+))\s*\)'
    for pattern in (calls, setters):
        for match in re.finditer(pattern, text, flags=re.S):
            literal = match.group(2) or match.group(3)
            variable = match.group(4)
            if literal:
                values.add(literal)
            elif variable in constants:
                values.add(constants[variable])
            elif variable and variable != "nil":
                dynamic.add(variable)
    return values, dynamic


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path, required=True)
    parser.add_argument("--oc-root", type=Path, help="organizedCategories Core root or its 42/media/lua directory")
    parser.add_argument("--oc-baseline", type=Path, default=OC_BASELINE,
                        help="reviewed source hash manifest (checked when --oc-root is supplied)")
    parser.add_argument("--mod-root", type=Path, help="selected mod source tree")
    parser.add_argument("--game", type=Path, help="game root or media/scripts directory")
    args = parser.parse_args()

    try:
        if not args.schema.is_file():
            raise ValueError(f"--schema must point to a file: {args.schema}")
        schema_text = args.schema.read_text()
    except (OSError, ValueError) as error:
        parser.error(str(error))
    known = category_keys(schema_text)
    if not known:
        parser.error("schema contains no category entries")
    if not any((args.oc_root, args.mod_root, args.game)):
        parser.error("at least one source root (--oc-root, --mod-root, or --game) is required")
    discovered, dynamic, en_keys = set(), set(), set()
    roots = []
    oc_root = None
    oc_source_root = None
    source_changes = []
    try:
        if args.oc_root:
            require_directory(args.oc_root, "--oc-root")
            oc_root = lua_roots(args.oc_root)[0]
            oc_source_root = organized_categories_source_root(args.oc_root)
            require_sources(oc_root, {".lua"}, "--oc-root")
            translation = oc_root / EN_TRANSLATION
            if not translation.is_file():
                raise ValueError(f"--oc-root is missing EN translation: {translation}")
            content = json.loads(translation.read_text())
            if not isinstance(content, dict):
                raise ValueError(f"EN translation must be a JSON object: {translation}")
            en_keys = {
                key.removeprefix("IGUI_ItemCat_") for key in content
                if key.startswith("IGUI_ItemCat_")
            }
            if not en_keys:
                raise ValueError(f"EN translation contains no IGUI_ItemCat_ keys: {translation}")
            baseline = load_baseline(args.oc_baseline)
            source_changes = baseline_changes(baseline["files"], taxonomy_fingerprints(oc_root))
            if baseline["schema_sha256"] != hashlib.sha256(args.schema.read_bytes()).hexdigest():
                source_changes.append("changed imported schema: " + str(args.schema))
            roots.append(oc_root)
        if args.mod_root:
            require_directory(args.mod_root, "--mod-root")
            require_sources(args.mod_root, {".lua", ".txt", ".script"}, "--mod-root")
            roots.append(args.mod_root)
        if args.game:
            scripts = game_scripts_root(args.game)
            require_sources(scripts, {".txt", ".script"}, "--game")
            roots.append(scripts)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))

    for root in roots:
        for path in source_files(root, {".lua", ".txt", ".script"}):
            if root != oc_root and oc_source_root and oc_source_root in path.parents:
                continue
            if path.suffix.lower() == ".lua":
                values, unresolved = inspect_lua(path)
                discovered.update(values)
                dynamic.update(unresolved)
            else:
                text = path.read_text(errors="replace")
                text = re.sub(r'/\*.*?\*/', "", text, flags=re.S)
                text = re.sub(r'//[^\n]*|#[^\n]*', "", text)
                discovered.update(
                    value for value in re.findall(
                        r'\bDisplayCategory\s*=\s*["\']?([A-Za-z_][A-Za-z0-9_]*)', text
                    ) if value.lower() != "nil"
                )

    missing = sorted(uncovered(discovered, known))
    missing_labels = sorted(uncovered(en_keys, known))
    print(f"schema categories: {len(known)}")
    if args.oc_root:
        print(f"organizedCategories EN labels: {len(en_keys)}; uncovered: {len(missing_labels)}")
        print("organizedCategories source baseline: " + ("REVIEW REQUIRED" if source_changes else "unchanged"))
        for change in source_changes:
            print(change)
    else:
        print("organizedCategories source baseline: not checked (--oc-root not supplied)")
    print(f"source category IDs: {len(discovered)}; uncovered: {len(missing)}")
    if dynamic:
        print("unresolved dynamic category variables: " + ", ".join(sorted(dynamic)))
    for category in missing_labels:
        print(f"missing EN category mapping: {category}")
    for category in missing:
        print(f"missing source category mapping: {category}")
    return 1 if missing or missing_labels or source_changes else 0


if __name__ == "__main__":
    sys.exit(main())
