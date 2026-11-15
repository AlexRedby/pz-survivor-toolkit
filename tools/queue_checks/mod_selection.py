"""Mod identities and active source layers shared by preparation and source checks."""
import re
from . import mod_inputs
from .game_version import game_version

MOD_ID = re.compile(r"[A-Za-z0-9_.-]+")
VERSION = re.compile(r"\d+(?:\.\d+)*")


def mod_ids(value):
    if not isinstance(value, str):
        raise ValueError('Selected pack contains invalid or duplicate Mod IDs')
    ids = value.split(';')
    if any(not MOD_ID.fullmatch(id) or id in ('.', '..') for id in ids) or len(ids) != len(set(ids)):
        raise ValueError('Selected pack contains invalid or duplicate Mod IDs')
    return ids


def metadata(path):
    return {key.strip(): value.strip() for line in path.read_text(encoding="utf-8-sig").splitlines()
            if "=" in line and not line.lstrip().startswith("#") for key, value in [line.split("=", 1)]}


def local_mod_infos(project):
    infos = list(project.glob("*/mod.info")) + list(project.glob("*/*/mod.info"))
    patches = project / "JavaPatches/build/PZToolkitJavaPatches"
    infos.extend(patches.glob("*/mod.info"))
    if (patches / "mod.info").is_file():
        infos.append(patches / "mod.info")
    return [path for path in infos if not mod_inputs.excluded(path.relative_to(project))]


def matching_roots(infos, identifier):
    roots = set()
    for info in infos:
        if metadata(info).get("id") == identifier:
            parent = info.parent
            roots.add((parent.parent if parent.name == "common" or VERSION.fullmatch(parent.name) else parent).resolve())
    return roots


def _version_int(name):
    # String.split drops trailing empty fields; PZMath.tryParseInt returns zero
    # for malformed/overflowing fields. Patch components have no selection role.
    parts = name.rstrip('.').split('.') if name.rstrip('.') else []
    def number(part):
        # PZMath.tryParseInt applies Java String.trim before Integer.parseInt.
        part = part.strip(''.join(chr(code) for code in range(33)))
        if not re.fullmatch(r'[+-]?\d+', part):
            return 0
        value = int(part)
        return value if -(2 ** 31) <= value < 2 ** 31 else 0
    if not parts:
        return 0
    value = number(parts[0]) * 1000 + min(number(parts[1]), 999) if len(parts) > 1 else number(parts[0]) * 1000
    return (value + 2 ** 31) % 2 ** 32 - 2 ** 31


def selected_mod_version(folder, version):
    """Mirror B42 ZomboidFileSystem.getModVersionDirName, including its default."""
    selected, minimum = folder / "42.0", 42000
    if (not isinstance(version, (tuple, list)) or not version
            or any(type(part) is not int or part < 0 for part in version)
            or version[0] != 42):
        raise ValueError('An explicit Build 42 engine version is required')
    maximum = _version_int(".".join(map(str, version)))
    for child in folder.iterdir():
        value = _version_int(child.name)
        # File.list, not listFiles/isDirectory: even a numeric regular-file
        # entry can select a nonexistent content layer instead of an older one.
        # Equal major/minor aliases keep filesystem enumeration order.
        if minimum <= value <= maximum:
            selected, minimum = child, value
    return selected


def mod_layers(folder, version):
    """B42 content overlays common with the selected version, never legacy root Lua."""
    selected = selected_mod_version(folder, version)
    return [path for path in (folder / "common", selected) if path.is_dir()]


def lua_sources(folder, version):
    """Effective Lua files: a selected version replaces the same common path."""
    effective = {}
    for layer in mod_layers(folder, version):
        lua = layer / 'media/lua'
        if lua.is_dir() or lua.is_symlink():
            effective.update({path.relative_to(lua): path for path in mod_inputs.files(lua) if path.suffix == '.lua'})
    return sorted(effective.values())


def mod_info(folder, version):
    # ChooseGameInfo probes the selected version, then common; root metadata
    # belongs to the legacy loader and cannot make a B42 mod discoverable.
    return next((layer / "mod.info" for layer in reversed(mod_layers(folder, version))
                 if (layer / "mod.info").is_file()), None)


def runtime_version(runtime):
    """Use the prepared engine version; legacy run data must supply its actual game JAR."""
    if 'game_version' not in runtime:
        return game_version(runtime.get('game'))
    version = runtime['game_version']
    if (not isinstance(version, (tuple, list)) or len(version) != 2
            or any(type(part) is not int for part in version)
            or version[0] != 42 or not 0 <= version[1] <= 999):
        raise ValueError('Invalid prepared engine mod-layer version')
    return tuple(version)
