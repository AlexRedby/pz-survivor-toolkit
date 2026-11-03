"""One membership policy for selected mod artifacts, distinct from strict run seals."""
import os
from pathlib import Path
import shutil
import stat
import re

from . import progress, snapshot_copy


POLICY = 'mod-artifacts-no-git-v1'


def excluded(relative):
    """Exclude only an exact .git entry; keep ordinary hidden runtime/build files."""
    return '.git' in Path(relative).parts


def _walk(root, *, strict):
    root = Path(root)
    if root.is_symlink():
        if strict:
            raise ValueError('Mod input symlinks are unsupported: ' + str(root))
        return
    if not root.is_dir():
        if strict:
            raise ValueError('Mod input root must be a directory: ' + str(root))
        return
    def failed(error):
        raise error
    for directory, names, files in os.walk(root, topdown=True, followlinks=False, onerror=failed):
        parent = Path(directory)
        retained = []
        for name in names:
            if excluded(name):
                continue
            path = parent / name
            if path.is_symlink():
                if strict:
                    raise ValueError('Mod input symlinks are unsupported: ' + str(path))
                continue
            retained.append(name)
        names[:] = retained
        yield parent, [name for name in files if not excluded(name)]


def files(root):
    result = []
    for parent, names in _walk(root, strict=True):
        for name in names:
            path = parent / name
            if path.is_symlink():
                raise ValueError('Mod input symlinks are unsupported: ' + str(path))
            if not stat.S_ISREG(path.stat().st_mode):
                raise ValueError('Mod inputs must be regular files: ' + str(path))
            result.append(path)
    return sorted(result)


def infos(root):
    """Discovery prunes Git but leaves unrelated, unselected links untraversed."""
    result = []
    for parent, names in _walk(root, strict=False):
        path = parent / 'mod.info'
        if 'mod.info' in names and not path.is_symlink() and path.is_file():
            result.append(path)
    return sorted(result)


def hashes(root):
    root = Path(root)
    result = {}
    for path in files(root):
        result[path.relative_to(root).as_posix()] = progress.hash_file(path)
        progress.file(path)
    return result


def manifest_files(rows):
    """Compare only native mod maps with the declared current membership policy."""
    from .mod_selection import MOD_ID
    if not isinstance(rows, list) or not rows:
        raise ValueError('Native mod manifest requires a fresh policy-bound snapshot')
    result = {}
    for row in rows:
        if (not isinstance(row, dict) or row.get('input_policy') != POLICY
                or not isinstance(row.get('id'), str) or not MOD_ID.fullmatch(row['id'])
                or row['id'] in ('.', '..') or row['id'] in result
                or not isinstance(row.get('files'), dict) or not row['files']):
            raise ValueError('Native mod manifest policy differs; prepare a fresh snapshot/seed')
        for name, value in row['files'].items():
            if (not isinstance(name, str) or not name or Path(name).is_absolute()
                    or Path(name).as_posix() != name or '..' in Path(name).parts
                    or excluded(name) or not isinstance(value, str) or not re.fullmatch('[0-9a-f]{64}', value)):
                raise ValueError('Invalid policy-bound native mod file map')
        result[row['id']] = row['files']
    return result


def _ignore(directory, names):
    return [name for name in names if excluded(name)]


def copy_tree(root, target):
    # Validate before creating output. A retained link appearing during copying
    # is copied as a link, never followed; strict native snapshot hashing rejects it.
    files(root)
    return shutil.copytree(root, target, ignore=_ignore, symlinks=True,
                           copy_function=snapshot_copy.copy_file)
