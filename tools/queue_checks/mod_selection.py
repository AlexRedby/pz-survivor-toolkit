"""Ordered Mod IDs used by installation preparation and native pack locks."""
import re

MOD_ID = re.compile(r"[A-Za-z0-9_.-]+")


def mod_ids(value):
    if not isinstance(value, str):
        raise ValueError('Selected pack contains invalid or duplicate Mod IDs')
    ids = value.split(';')
    if any(not MOD_ID.fullmatch(id) or id in ('.', '..') for id in ids) or len(ids) != len(set(ids)):
        raise ValueError('Selected pack contains invalid or duplicate Mod IDs')
    return ids
