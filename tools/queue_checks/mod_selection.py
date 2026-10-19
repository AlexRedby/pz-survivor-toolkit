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


def mod_layers(folder, version=(42, 21)):
    """Content layers in overlay order; B42 content never falls back to legacy root Lua."""
    versions = [(tuple(map(int, child.name.split("."))), child) for child in folder.iterdir()
                if child.is_dir() and VERSION.fullmatch(child.name)]
    compatible = [(v, path) for v, path in versions if (42,) <= v <= version]
    if versions:
        if not compatible:
            return []
        return [path for path in (folder / "common", max(compatible)[1]) if path.is_dir()]
    return [folder / "common"] if (folder / "common").is_dir() else [folder]


def mod_info(folder, version=(42, 21)):
    layers = mod_layers(folder, version)
    if not layers:
        return None
    # Root metadata is a fallback, unlike legacy root content in a B42 mod.
    return next((layer / "mod.info" for layer in [*reversed(layers), folder]
                 if (layer / "mod.info").is_file()), None)
