"""Independent mod-snapshot files, sharing unchanged blocks where macOS permits."""
import ctypes
import errno
import os
import shutil
import stat
import sys


def _load_clonefile():
    if sys.platform != 'darwin':
        return None
    try:
        clone = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True).clonefile
    except (OSError, AttributeError):
        return None
    clone.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int)
    clone.restype = ctypes.c_int
    return clone


_CLONEFILE = _load_clonefile()
_COPY_FALLBACK = {errno.ENOTSUP, errno.EOPNOTSUPP, errno.EXDEV, errno.ENOSYS, errno.EEXIST}


def copy_file(src, dst):
    """Copy with copy2 semantics; clones have their own inode and private writes."""
    # clonefile can clone whole directory trees. Leave non-regular sources and
    # symlink handling to copy2 instead; native source hashing rejects symlinks.
    if _CLONEFILE is not None and stat.S_ISREG(os.stat(src, follow_symlinks=False).st_mode):
        if _CLONEFILE(os.fsencode(src), os.fsencode(dst), 0) == 0:
            shutil.copystat(src, dst)
            return dst
        error = ctypes.get_errno()
        # Existing destinations use copy2's overwrite rules. Real I/O failures
        # must stop preparation rather than retrying an allocating copy.
        if error not in _COPY_FALLBACK:
            raise OSError(error, os.strerror(error), os.fspath(src), None, os.fspath(dst))
    return shutil.copy2(src, dst)
