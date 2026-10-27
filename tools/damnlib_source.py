"""Retire duplicate battery recipes from a reviewed complete DAMN Library copy."""

from pathlib import Path

try:
    from .dependency_source import prepare_source_patch
except ImportError:
    from dependency_source import prepare_source_patch


PATCH_ID = "damnlib-native-battery-recipes-v1"
ORIGINAL_SOURCE_SHA256 = "0f26406851c62525a913a2e41ead186b43591993c5ad3547f3249274a61b6c93"
PATCHED_SOURCE_SHA256 = "1fcf8efeb8439f8cbc2ed8ddba7264336321d92adccfc97f6061d374eb6f14a3"
TARGET = Path("media/scripts/damnCraft/recipes_damnCraft.txt")
_START = b"    craftRecipe damnCraftRemoveBatteryFromPlasticWeldingGun\r\n"
_NEXT = b"    /************************ Rubber Mounts ************************/"


def _patched(source: bytes) -> bytes:
    if source.count(_START) != 1 or source.count(_NEXT) != 1:
        raise ValueError("Reviewed DAMN Library battery recipe boundary changed")
    start, end = source.index(_START), source.index(_NEXT)
    removed = source[start:end]
    if end <= start or removed.count(b"craftRecipe ") != 2 or removed.count(
            b"craftRecipe damnCraftInsertBatteryIntoPlasticWeldingGun\r\n") != 1:
        raise ValueError("Reviewed DAMN Library battery recipe section changed")
    # The normal Base recipes already match the gun's base:usesbattery tag.
    return source[:start] + source[end:]


def prepare_damnlib(source_root: Path, destination: Path, game_version: str = "42.21") -> dict:
    return prepare_source_patch(source_root, destination, mod_id="damnlib", target=TARGET,
                                original_sha256=ORIGINAL_SOURCE_SHA256,
                                patched_sha256=PATCHED_SOURCE_SHA256, patch_id=PATCH_ID,
                                transform=_patched, game_version=game_version)
