"""Mod identities and active source layers shared by preparation and source checks."""
import re

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
    return infos


def matching_roots(infos, identifier):
    roots = set()
    for info in infos:
        if metadata(info).get("id") == identifier:
            parent = info.parent
            roots.add((parent.parent if parent.name == "common" or VERSION.fullmatch(parent.name) else parent).resolve())
    return roots


def _version_int(name):
    parts = name.split(".")
    minor = int(parts[1]) if len(parts) > 1 else 0
    return int(parts[0]) * 1000 + min(minor, 999)


def selected_mod_version(folder, version=(42, 21)):
    """Mirror B42 ZomboidFileSystem.getModVersionDirName, including its default."""
    selected, minimum = folder / "42.0", 42000
    maximum = _version_int(".".join(map(str, version)))
    for child in folder.iterdir():
        if child.is_dir() and VERSION.fullmatch(child.name):
            value = _version_int(child.name)
            # The engine ignores patch components and keeps the last equal
            # major/minor alias in filesystem enumeration order.
            if minimum <= value <= maximum:
                selected, minimum = child, value
    return selected


def mod_layers(folder, version=(42, 21)):
    """B42 content overlays common with the selected version, never legacy root Lua."""
    selected = selected_mod_version(folder, version)
    return [path for path in (folder / "common", selected) if path.is_dir()]


def mod_info(folder, version=(42, 21)):
    # ChooseGameInfo probes the selected version, then common; root metadata
    # belongs to the legacy loader and cannot make a B42 mod discoverable.
    return next((layer / "mod.info" for layer in reversed(mod_layers(folder, version))
                 if (layer / "mod.info").is_file()), None)
