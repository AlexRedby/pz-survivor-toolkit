"""Prepare isolated, immutable inputs for the native queue test runner."""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile
from . import adapters, worlds, pack, admission, report, coop


VERSION = re.compile(r"\d+(?:\.\d+)*")
MOD_ID = re.compile(r"[A-Za-z0-9_.-]+")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hashes(root):
    paths = sorted(root.rglob("*"))
    for path in [root, *paths]:
        if path.is_symlink():
            raise ValueError('Hashed input symlinks are unsupported: ' + str(path))
    return {path.relative_to(root).as_posix(): sha256(path) for path in paths if path.is_file()}


def _json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _metadata(path):
    return {key.strip(): value.strip() for line in path.read_text(encoding="utf-8-sig").splitlines()
            if "=" in line and not line.lstrip().startswith("#") for key, value in [line.split("=", 1)]}


def font_preload(cache, selection):
    """Explicit local-JAR opt-in; ordinary approvals do not grant signed early loading."""
    enabled = selection.get('options', {}).get('preload_toolkit_fonts', False)
    if type(enabled) is not bool:
        raise ValueError('preload_toolkit_fonts must be boolean')
    if not enabled:
        return ''
    if not {'ZombieBuddy', 'PZToolkitJavaPatches'} <= set(selection['mods']):
        raise ValueError('Font preload requires selected ZombieBuddy and PZToolkitJavaPatches')
    layer = Path(cache) / 'mods/PZToolkitJavaPatches/42'
    info = _metadata(layer / 'mod.info')
    package = 'net.alexredby.pztoolkitbootstrap'
    if (info.get('id'), info.get('javaPkgName'), info.get('javaJarFile')) != (
            'PZToolkitJavaPatches', 'net.alexredby.pztoolkitjavapatches', 'media/java/PZToolkitJavaPatches.jar'):
        raise ValueError('Font preload requires the selected early-font bootstrap metadata')
    jar = layer / 'media/bootstrap/PZToolkitFonts.jar'
    if any(char in str(jar) for char in (',', ':', ';', '\n', '\r')):
        raise ValueError('Font preload path contains loader separators')
    with zipfile.ZipFile(jar) as archive:
        manifest = archive.read('META-INF/MANIFEST.MF').decode('utf-8')
        if not re.search(r'^ZB-Preload: true\r?$', manifest, re.M):
            raise ValueError('Font preload requires ZB-Preload manifest')
    return ',patches_jar=' + str(jar) + ':' + package


def _approvals(cache, identifiers):
    return [{'id': id, 'jar_hash': sha256(jar), 'decision': True, 'time': '2026-01-01T00:00:00Z'}
            for id in identifiers for jar in sorted((cache / 'mods' / id).rglob('*.jar'))
            # This separate bootstrap is loaded only by explicit patches_jar, never as the ordinary mod.
            if not (id == 'PZToolkitJavaPatches' and jar.relative_to(cache / 'mods' / id).as_posix()
                    == '42/media/bootstrap/PZToolkitFonts.jar')]


def _mod_root(info):
    parent = info.parent
    return parent.parent if parent.name == "common" or VERSION.fullmatch(parent.name) else parent


def _matching_roots(infos, identifier):
    return {_mod_root(info).resolve() for info in infos
            if _metadata(info).get("id", "").strip() == identifier}


def _locations(project, workshop, identifiers, overrides=None):
    overrides = {} if overrides is None else overrides
    if not isinstance(overrides, dict) or any(not isinstance(id, str) or not isinstance(path, (str, Path))
            or not Path(path).is_absolute() for id, path in overrides.items()):
        raise ValueError('Mod source overrides must map Mod IDs to absolute paths')
    if set(overrides) - set(identifiers):
        raise ValueError('Mod source override is not selected')
    local_infos = list(project.glob("*/mod.info")) + list(project.glob("*/*/mod.info"))
    local_infos += list((project / "JavaPatches/build/PZToolkitJavaPatches").glob("*/mod.info"))
    patch_info = project / "JavaPatches/build/PZToolkitJavaPatches/mod.info"
    if patch_info.is_file():
        local_infos.append(patch_info)
    remote_infos = []
    for root in dict.fromkeys(path.resolve() for path in workshop):
        if not root.is_dir():
            raise ValueError("Workshop root does not exist: " + str(root))
        remote_infos.extend(root.rglob("mod.info"))
    result = {}
    for identifier in identifiers:
        if identifier in overrides:
            explicit = Path(overrides[identifier]).resolve()
            found = _matching_roots(explicit.rglob('mod.info'), identifier) if explicit.is_dir() else set()
        else:
            found = _matching_roots(local_infos, identifier)
        if not found and identifier not in overrides:
            found = _matching_roots(remote_infos, identifier)
        if len(found) != 1:
            raise ValueError("Mod ID must resolve exactly once: " + identifier + ": " + str(sorted(map(str, found))))
        root = next(iter(found))
        versions = [(tuple(map(int, child.name.split("."))), child) for child in root.iterdir()
                    if child.is_dir() and VERSION.fullmatch(child.name)]
        compatible = [(version, child) for version, child in versions if (42,) <= version <= (42, 21)]
        if versions and not compatible:
            raise ValueError("No compatible 42.21 mod layer: " + identifier)
        layers = [max(compatible)[1], root / "common", root] if compatible else [root / "common", root]
        info = next((layer / "mod.info" for layer in layers if (layer / "mod.info").is_file()), None)
        if info is None or _metadata(info).get("id") != identifier:
            raise ValueError("Selected version has a different Mod ID: " + identifier)
        result[identifier] = root
    return result


def _validate(selection):
    coop.enabled(selection)
    suite = selection.get("suite")
    if type(selection.get("schema_version")) is not int or selection["schema_version"] != 1 or not isinstance(suite, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*", suite):
        raise ValueError("Expected schema_version=1 and a valid suite name")
    if selection.get("kind") not in ("sp", "mp") or selection.get("mode") not in ("toolkit", "native"):
        raise ValueError("Expected kind=sp|mp and mode=toolkit|native")
    for key in ("cases", "mods"):
        values = selection.get(key)
        empty_control = key == 'mods' and suite == 'startup' and selection['mode'] == 'native'
        if not isinstance(values, list) or not values and not empty_control or any(not isinstance(value, str) or not MOD_ID.fullmatch(value) or value in ('.', '..') for value in values):
            raise ValueError("Expected nonempty IDs in " + key)
        if len(values) != len(set(values)):
            raise ValueError("Duplicate IDs in " + key)
    if "ActionQueueTest" in selection["mods"]:
        raise ValueError("ActionQueueTest is reserved for the native fixture")
    if selection['suite'] == 'health' and "PZSurvivorToolkit" not in selection["mods"]:
        raise ValueError("Native queue modes require PZSurvivorToolkit with its queue option toggled")
    languages = selection.get("languages")
    clients = selection.get('clients', 2 if selection['kind'] == 'mp' else 1)
    if type(clients) is not int or clients not in (1, 2) or selection['kind'] == 'sp' and clients != 1 or languages not in (["EN"], ["RU"], ["EN", "RU"]) or len(languages) != clients:
        raise ValueError('Provide one language per actual client; SP has one, MP one or two')
    if selection['suite'] == 'health' and selection['kind'] == 'mp' and languages != ['EN', 'RU']:
        raise ValueError('Health MP requires both EN and RU')
    admission.budget(selection)
    ports = selection.get("ports")
    if not isinstance(ports, list) or len(ports) != 2 or len(set(ports)) != 2 or any(type(port) is not int or not 1024 <= port <= 65535 for port in ports):
        raise ValueError("Expected two distinct unprivileged ports")
    if type(selection.get("timeout_seconds")) is not int or selection["timeout_seconds"] <= 0:
        raise ValueError("Expected a positive timeout_seconds")
    if selection.get("expected_checks") != len(selection["cases"]) + 2:
        raise ValueError("expected_checks must equal selected cases plus two setup checks")


def _lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, dict):
        return "{" + ",".join("[" + _lua(key) + "]=" + _lua(item) for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(map(_lua, value)) + "}"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if type(value) is bool:
        return "true" if value else "false"
    if type(value) is int:
        return str(value)
    if type(value) is float and math.isfinite(value):
        return repr(value)
    raise ValueError("Unsupported Lua selection value: " + repr(value))


def prepare(project: Path, output: Path, game: Path, jdk: Path,
            selection: dict, workshop: list[Path] = ()) -> Path:
    """Return a fresh snapshot directory; never reuse or change an earlier run."""
    project, output, game, jdk = (Path(path).resolve() for path in (project, output, game, jdk))
    if output.exists():
        raise FileExistsError("Fresh output directory required: " + str(output))
    if selection.get('ports_auto') and selection.get('options', {}).get('world_template'):
        world_ports = json.loads((Path(selection['options']['world_template']) / 'world.json').read_text())['ports']
        # Saved MP client identities require the template endpoint, not a new automatic pair.
        selection = dict(selection, ports=world_ports, ports_auto=False)
    if selection.get('ports_auto') and selection.get('options', {}).get('seed_run'):
        selection = dict(selection, ports=json.loads((Path(selection['options']['seed_run']) / 'selection.json').read_text())['ports'])
    _validate(selection)
    for path in (game / "projectzomboid.jar", jdk / "bin/java", jdk / "bin/javac"):
        if not path.is_file():
            raise ValueError("Missing game/JDK file: " + str(path))
    for binary in ("java", "javac"):
        if not os.access(jdk / "bin" / binary, os.X_OK):
            raise ValueError("JDK binary is not executable: " + str(jdk / "bin" / binary))
    if not (game / "media/lua").is_dir():
        raise ValueError("Missing native game Lua sources: " + str(game / "media/lua"))
    if "ZombieBuddy" in selection["mods"] and not (game / "ZombieBuddy.jar").is_file():
        raise ValueError("Selected ZombieBuddy requires the installed game/ZombieBuddy.jar agent")
    adapter = adapters.get(selection['suite'])
    if adapter:
        adapter.validate(selection)
    overrides = selection.get('options', {}).get('mod_sources', {})
    locked = selection.get('options', {}).get('pack_lock')
    if locked:
        pinned = pack.validate(locked, project, game, selection['mods'])
        if any(id not in pinned or Path(path).resolve() != Path(pinned[id]).resolve() for id, path in overrides.items()):
            raise ValueError('Mod override differs from pack lock; regenerate the lock explicitly')
        overrides = pinned
    locations = _locations(project, list(map(Path, workshop)), selection["mods"], overrides)
    template = selection.get('options', {}).get('world_template')
    world = None
    if template:
        if not isinstance(template, str) or not Path(template).is_absolute():
            raise ValueError('world_template must be an absolute saved template path')
        if selection.get('options', {}).get('seed_run'):
            raise ValueError('Choose world_template or scenario seed_run, not both')
        template, world = worlds.validate(template, selection, game)
        if output.is_relative_to(template):
            raise ValueError('Run output must be outside the world template')
    if any(output.is_relative_to(source) for source in [game, jdk, *locations.values()]):
        raise ValueError("Output must be outside game, JDK and source mod directories")
    if any(char in str(path) for path in (output, game, jdk) for char in (",", ":", "\n", "\r")):
        raise ValueError("Runtime paths cannot contain loader/classpath separators or newlines")
    support = project / "tests/native_queue/support"
    suite = project / "tests/native_queue" / selection["suite"]
    required = [support / name for name in ("ToolkitSmokeLauncher.java", "ZZReleasePreflight.lua", "QueueEnergyPlacement.lua")]
    required += [project / "tools/check_action_queue.py", project / "tests/native_queue/catalog.json"]
    if not adapter and (not (suite / "client").is_dir() or not (suite / "shared").is_dir() or selection["kind"] == "mp" and not (suite / "server").is_dir()):
        raise ValueError("Native suite is missing its client/shared/server source directories: " + str(suite))
    for path in required:
        if not path.is_file():
            raise ValueError("Missing native support source: " + str(path))
    for source in locations.values():
        if output.is_relative_to(source):
            raise ValueError("Snapshot output cannot be inside a selected mod")
    sources = required + sorted(suite.rglob("*.lua")) + sorted((project / "tools/queue_checks").glob("*.py")) + [Path(__file__).resolve(), game / "projectzomboid.jar", jdk / "bin/java", jdk / "bin/javac"]
    sources.append(Path(adapters.__file__))
    if adapter:
        sources += [Path(adapter.__file__), *map(Path, adapter.sources(project, selection))]
        for relative in adapter.definitions()[selection['suite']].get('game_inputs', []):
            asset = (game / relative).resolve()
            if not asset.is_relative_to(game):
                raise ValueError('Game input escapes installed game: ' + relative)
            sources.append(asset)
    if coop.enabled(selection) and project / 'tests/native_queue/startup/client/ZZStartup.lua' not in sources:
        raise ValueError('Host requires a suite using the common startup bootstrap')
    if selection.get('config_source'):
        sources.append(Path(selection['config_source']))
    if "ZombieBuddy" in selection["mods"]:
        sources.append(game / "ZombieBuddy.jar")
    if world:
        sources += [template / 'world.json', *[template / 'state' / name for name in world['files']]]
    if locked:
        sources += [Path(locked), project / 'SurvivorQoL-selected.ini']
    # File membership matters too: newly added Lua/scripts are live game inputs.
    game_input_manifest = report.game_inputs(game)
    sources += [game / tree / name for tree, files in game_input_manifest['trees'].items() for name in files]
    source_manifest = {str(path): sha256(path) for path in sources}
    manifest = [{"id": identifier, "source": str(source), "files": hashes(source)}
                for identifier, source in locations.items()]
    for row in manifest:
        source_manifest.update({str(Path(row["source"]) / relative): digest for relative, digest in row["files"].items()})
    roles = adapters.roles(selection)
    # copytree materializes logical file sizes, including sparse files; allow allocation/metadata overhead.
    def copy_size(paths):
        return sum(((path.stat().st_size + 4095) // 4096 + 1) * 4096 for path in paths)

    mod_bytes = sum(copy_size(Path(row['source']) / name for name in row['files']) for row in manifest)
    fixture_bytes = copy_size(path for path in sources if path.is_relative_to(project) and path.is_file())
    world_bytes = copy_size(template / 'state' / name for name in world['files']) if world else 0
    admission.require_disk(output, len(roles), len(roles) * (mod_bytes + fixture_bytes) + world_bytes)
    runtime = {"project": str(project), "game": str(game), "jdk": str(jdk), "kind": selection["kind"], 'fixture': {'mods': []},
               "java": str(jdk / "bin/java"), "server_name": "queue-smoke", "roles": {}}
    output.mkdir(parents=True)
    if selection.get('ports_auto'):
        selection = dict(selection, ports=admission.allocate_ports(output, selection) if selection['kind'] == 'mp' else [17343, 17344])
    for index, role in enumerate(roles):
        admission.require_disk(output, len(roles), (len(roles) - index) * (mod_bytes + fixture_bytes) + world_bytes)
        cache = output / role
        for directory in ("mods", "Lua", "classes", "zombie-buddy"):
            (cache / directory).mkdir(parents=True)
        for identifier, source in locations.items():
            target = cache / "mods" / identifier
            shutil.copytree(source, target)
            expected = next(row["files"] for row in manifest if row["id"] == identifier)
            if hashes(target) != expected:
                raise RuntimeError("Mod changed while copying snapshot: " + identifier)
            versions = [p for p in target.iterdir() if p.is_dir() and VERSION.fullmatch(p.name)]
            layers = [target, target / 'common', *versions]
            if not versions and (target / 'common/mod.info').is_file():
                # B42 still scans its default 42.0 layer when all mod content is common.
                layers.append(target / '42.0')
            for layer in layers:
                if layer != target or (layer / "media").is_dir():
                    for sub in ("AnimSets", "actiongroups"):
                        (layer / "media" / sub).mkdir(parents=True, exist_ok=True)
        helper = cache / "mods/ActionQueueTest"
        for layer in ("common", "42"):
            for sub in ("AnimSets", "actiongroups"):
                (helper / layer / "media" / sub).mkdir(parents=True)
        (helper / "42/mod.info").write_text("name=Isolated native queue test\nid=ActionQueueTest\nversionMin=42.21\n", encoding="utf-8")
        lua = helper / "42/media/lua"
        for side in ("shared", "client", "server"):
            (lua / side).mkdir(parents=True, exist_ok=True)
            if (suite / side).is_dir():
                shutil.copytree(suite / side, lua / side, dirs_exist_ok=True)
        shutil.copy2(support / "ZZReleasePreflight.lua", lua / "client")
        shutil.copy2(support / "QueueEnergyPlacement.lua", lua / "shared")
        language = selection["languages"][-1] if role == "client2" else selection["languages"][0]
        # Shared Lua must be byte-identical for native MP checksums; role/language live in cache/Lua.
        config = dict(selection, port=selection["ports"][0], resources=dict(admission.DEFAULTS, **selection.get('resources', {})))
        (lua / "shared/QueueTestSelection.lua").write_text("QueueTestSelection=" + _lua(config) + "\nreturn QueueTestSelection\n", encoding="utf-8")
        for name, value in {"smoke-user": role, "queue-mode": selection["mode"], "queue-scenario": selection["suite"],
                            "queue-health-kind": selection["kind"], "queue-health-language": language,
                            "queue-health-start": selection["cases"][0], "queue-expected-mods": "\n".join(selection["mods"])}.items():
            (cache / "Lua" / (name + ".txt")).write_text(value + "\n", encoding="utf-8")
        (cache / "mods/default.txt").write_text("VERSION = 1,\nmods\n{\n" + "".join(" mod = " + mod + ",\n" for mod in [*selection["mods"], "ActionQueueTest"]) + "}\nmaps\n{\n}\n", encoding="utf-8")
        (cache / "mods/reset-mods-42_00.txt").write_text("Keep isolated native queue fixture selection.\n", encoding="utf-8")
        (cache / "options.ini").write_text("version=10\nwidth=1280\nheight=720\nfullScreen=false\nborderless=false\nmusicVolume=0\nsoundVolume=0\njumpScareVolume=0\nvehicleEngineVolume=0\nvoiceEnable=false\npauseOnFocusLoss=false\nlanguage=" + language + "\n", encoding="utf-8")
        approvals = _approvals(cache, locations)
        _json(cache / "zombie-buddy/mod_approvals.json", {"formatVersion": 2, "mods": approvals})
        runtime["roles"][role] = {"cache": str(cache), "language": language}
        if role != "server":
            font_preload(cache, selection)
            shutil.copy2(support / "ToolkitSmokeLauncher.java", cache / "classes")
            subprocess.run([str(jdk / "bin/javac"), "-cp", str(game / "projectzomboid.jar"),
                            str(cache / "classes/ToolkitSmokeLauncher.java")], check=True, capture_output=True, text=True, timeout=60,
                           env={key: value for key, value in os.environ.items() if key not in ("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS")})
            if not (cache / "classes/ToolkitSmokeLauncher.class").is_file():
                raise RuntimeError("javac did not create ToolkitSmokeLauncher.class")
            runtime["roles"][role]["classes"] = str(cache / "classes")
    if selection["kind"] == "mp":
        server = output / "server/Server"
        server.mkdir()
        (server / "queue-smoke.ini").write_text("Mods=" + ";".join([*selection["mods"], "ActionQueueTest"]) + "\nWorkshopItems=\nMap=Muldraugh, KY\nDefaultPort=" + str(selection["ports"][0]) + "\nUDPPort=" + str(selection["ports"][1]) + "\nPublic=false\nUPnP=false\nOpen=true\nAutoCreateUserInWhiteList=true\nMaxPlayers=4\nPVP=false\nSpawnPoint=10835,10144,0\nPauseEmpty=true\nDoLuaChecksum=true\nSleepAllowed=false\nSleepNeeded=false\nVoiceEnable=false\n", encoding="utf-8")
        (server / "queue-smoke_SandboxVars.lua").write_text("SandboxVars={VERSION=6,Zombies=6,StartMonth=7,StartDay=9,StartTime=2,MinutesPerPage=2.0}\n", encoding="utf-8")
        if locked:
            settings = _metadata(project / 'SurvivorQoL-selected.ini')
            path = server / 'queue-smoke.ini'
            text = path.read_text()
            for key in ('Map', 'PVP', 'DoLuaChecksum', 'SleepAllowed', 'SleepNeeded'):
                if key not in settings:
                    continue
                value = settings[key]
                if not value or key != 'Map' and value not in ('true', 'false'):
                    raise ValueError('Invalid selected-pack setting: ' + key)
                if key == 'DoLuaChecksum' and value != 'true':
                    raise ValueError('Native fixtures require DoLuaChecksum=true')
                text = re.sub(r'^' + key + r'=.*\n?', '', text, flags=re.M).rstrip('\n') + '\n' + key + '=' + value + '\n'
            path.write_text(text)
    if world:
        worlds.restore(template, world, output, runtime)
    if adapter:
        adapter.stage(project, output, game, jdk, selection, locations, runtime)
    admission.require_disk(output, len(roles))
    for role in roles:
        path = output / role / 'options.ini'
        settings = path.read_text()
        for key, value in {'soundVolume': '0', 'musicVolume': '0', 'jumpScareVolume': '0',
                           'vehicleEngineVolume': '0', 'voiceEnable': 'false'}.items():
            settings = re.sub(r'^' + key + r'=.*\n?', '', settings, flags=re.M)
            settings = settings.rstrip('\n') + '\n' + key + '=' + value + '\n'
        path.write_text(settings)
    if selection['kind'] == 'mp' and runtime['fixture'].get('sandbox'):
        path = output / 'server/Server/queue-smoke_SandboxVars.lua'
        values = {'VERSION': 6, 'Zombies': 6, 'StartMonth': 7, 'StartDay': 9, 'StartTime': 2, 'MinutesPerPage': 2}
        values.update(runtime['fixture']['sandbox'])
        # Sandbox settings are explicit numeric/boolean suite inputs, sealed below.
        text = ','.join(key + '=' + ('true' if value else 'false') if type(value) is bool else key + '=' + str(value) for key, value in values.items())
        path.write_text('SandboxVars={' + text + '}\n')
    if world:
        worlds.verify_settings(world, output, runtime)
    extra = runtime['fixture'].get('mods', [])
    if not isinstance(extra, list) or len(set(extra)) != len(extra) or any(not isinstance(id, str) or not MOD_ID.fullmatch(id) or id in selection['mods'] or id == 'ActionQueueTest' for id in extra):
        raise ValueError('Invalid or duplicate generated fixture Mod IDs')
    active = [*selection['mods'], 'ActionQueueTest', *extra]
    for role in roles:
        cache = output / role
        for id in extra:
            if not (cache / 'mods' / id).is_dir():
                raise ValueError('Generated fixture mod missing: ' + role + '/' + id)
            for layer in ('common', '42'):
                for directory in ('AnimSets', 'actiongroups'):
                    (cache / 'mods' / id / layer / 'media' / directory).mkdir(parents=True, exist_ok=True)
        (cache / 'mods/default.txt').write_text('VERSION = 1,\nmods\n{\n' + ''.join(' mod = ' + id + ',\n' for id in active) + '}\nmaps\n{\n}\n')
        approvals = _approvals(cache, active)
        _json(cache / 'zombie-buddy/mod_approvals.json', {'formatVersion': 2, 'mods': approvals})
    if selection['kind'] == 'mp':
        path = output / 'server/Server/queue-smoke.ini'
        text = re.sub(r'^Mods=.*$', 'Mods=' + ';'.join(active), path.read_text(), flags=re.M)
        path.write_text(text)
    if coop.enabled(selection):
        coop.stage(output, runtime)
    _json(output / "selection.json", selection)
    if locked:
        pack.validate(locked, project, game, selection['mods'])
    _json(output / "manifest.json", manifest)
    _json(output / "source-manifest.json", source_manifest)
    _json(output / 'game-inputs.json', game_input_manifest)
    _json(output / "runtime.json", runtime)
    initial_settings = {path.relative_to(output).as_posix(): path.read_text(encoding="utf-8")
                        for role in roles for path in [output / role / "options.ini", *sorted((output / role / "Server").glob("*"))]
                        if path.is_file()}
    _json(output / "initial-settings.json", initial_settings)
    comparison = {"selection": {key: value for key, value in selection.items() if key != "mode"},
                  "mods": {row["id"]: row["files"] for row in manifest}, "sources": source_manifest,
                  "settings": initial_settings, "game_inputs": game_input_manifest}
    if selection.get('config_source'):
        config_path = selection['config_source']
        comparison['selection'] = dict(comparison['selection'], config_source='<suite-config>')
        comparison['sources'] = dict(source_manifest)
        comparison['sources']['<suite-config>'] = comparison['sources'].pop(config_path)
    if selection.get('ports_auto'):
        comparison['selection']['ports'] = '<automatic-endpoint>'
        comparison['settings'] = {name: re.sub(r'^(DefaultPort|UDPPort)=\d+$', r'\1=<automatic-endpoint>', text, flags=re.M)
                                  for name, text in initial_settings.items()}
    fingerprint = hashlib.sha256(json.dumps(comparison, sort_keys=True).replace(str(output), '<run>').encode()).hexdigest()
    _json(output / "settings-fingerprint.json", {"sha256": fingerprint, "inputs": comparison})
    if report.game_inputs(game) != game_input_manifest:
        raise RuntimeError('Native Lua/script inputs changed while preparing snapshot')
    for path, digest in source_manifest.items():
        if sha256(Path(path)) != digest:
            raise RuntimeError("Source changed while preparing snapshot: " + path)
    frozen = {path.name: sha256(path) for path in sorted(output.iterdir()) if path.is_file()}
    for role in roles:
        for directory in ("mods", "classes", "Lua"):
            frozen.update({role + "/" + directory + "/" + relative: digest
                           for relative, digest in hashes(output / role / directory).items()})
    _json(output / "snapshot-hashes.json", frozen)
    return output
