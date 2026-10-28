"""Bounded, read-only metadata for one owned macOS GUI process.

Only the helper process loads CoreGraphics: a stuck or crashing native call must
not prevent the runner from cleaning up its client. No accessibility, screen
capture, window titles or application identity are requested.
"""
import ctypes
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile

TIMEOUT_SECONDS = 1.5
MAX_OUTPUT_BYTES = 65536
MAX_ENUMERATED_WINDOWS = 8192
MAX_OWNED_WINDOWS = 128
MAX_DISPLAYS = 128


def _valid_pid(pid):
    return type(pid) is int and 0 < pid <= 2147483647


def _empty(pid, status, reason):
    return {'status': status, 'reason': reason, 'pid': pid if _valid_pid(pid) else None,
            'display': {'state': 'unknown', 'displays': []},
            'session': {'status': 'unavailable', 'screen_locked': None,
                        'on_console': None, 'login_done': None},
            'windows': {'status': 'unavailable', 'items': []}}


def _number(value):
    return (type(value) in (int, float) and math.isfinite(value)
            and abs(value) <= 1e12)


def _sanitize(value, pid):
    """Allowlist the helper protocol again before any result can be persisted."""
    if not isinstance(value, dict) or value.get('pid') != pid or type(value.get('pid')) is not int:
        raise ValueError('invalid-helper-envelope')
    status = value.get('status')
    if status not in ('returned', 'unavailable', 'error'):
        raise ValueError('invalid-helper-status')
    result = _empty(pid, status, 'helper-' + status)
    # Reasons are finite identifiers; never propagate exception text or native data.
    if value.get('reason') in ('not-macos', 'invalid-pid', 'native-probe-failed'):
        result['reason'] = value['reason']
    display = value.get('display')
    if isinstance(display, dict) and display.get('state') in ('awake', 'asleep', 'unknown'):
        rows = display.get('displays')
        if isinstance(rows, list) and len(rows) <= MAX_DISPLAYS:
            clean = []
            for row in rows:
                if (not isinstance(row, dict) or type(row.get('id')) is not int
                        or not 0 < row['id'] <= 4294967295 or type(row.get('asleep')) is not bool):
                    clean = None
                    break
                clean.append({'id': row['id'], 'asleep': row['asleep']})
            if clean is not None and len({row['id'] for row in clean}) == len(clean):
                state = display['state']
                if (state == 'unknown' or clean and
                        (state == 'asleep') == all(row['asleep'] for row in clean)):
                    result['display'] = {'state': state, 'displays': clean}
    session = value.get('session')
    if isinstance(session, dict) and session.get('status') in ('returned', 'unavailable', 'error'):
        result['session']['status'] = session['status']
        for key in ('screen_locked', 'on_console', 'login_done'):
            if session['status'] == 'returned' and type(session.get(key)) is bool:
                result['session'][key] = session[key]
    windows = value.get('windows')
    if isinstance(windows, dict) and windows.get('status') in ('returned', 'unavailable', 'error', 'limited'):
        rows = windows.get('items')
        if not isinstance(rows, list) or len(rows) > MAX_OWNED_WINDOWS:
            raise ValueError('invalid-helper-windows')
        result['windows']['status'] = windows['status']
        for row in rows if windows['status'] in ('returned', 'limited') else []:
            if not isinstance(row, dict) or type(row.get('pid')) is not int or row['pid'] != pid:
                continue
            item = {'pid': pid, 'id': None, 'layer': None, 'alpha': None,
                    'onscreen': None, 'bounds': None}
            if type(row.get('id')) is int and 0 < row['id'] <= 4294967295:
                item['id'] = row['id']
            if type(row.get('layer')) is int and abs(row['layer']) <= 2147483647:
                item['layer'] = row['layer']
            if _number(row.get('alpha')) and 0 <= row['alpha'] <= 1:
                item['alpha'] = row['alpha']
            if type(row.get('onscreen')) is bool:
                item['onscreen'] = row['onscreen']
            bounds = row.get('bounds')
            if (isinstance(bounds, dict) and all(_number(bounds.get(key)) for key in ('x', 'y', 'width', 'height'))
                    and bounds['width'] >= 0 and bounds['height'] >= 0):
                item['bounds'] = {key: bounds[key] for key in ('x', 'y', 'width', 'height')}
            result['windows']['items'].append(item)
    return result


def capture(pid):
    """Return allowlisted incident metadata, or a failure value, within 1.5s of helper execution."""
    if not _valid_pid(pid):
        return _empty(pid, 'error', 'invalid-pid')
    if sys.platform != 'darwin':
        return _empty(pid, 'unavailable', 'not-macos')
    try:
        # A file avoids unbounded PIPE buffering; only a capped payload is read.
        with tempfile.TemporaryFile() as output:
            completed = subprocess.run([sys.executable, '-I', str(Path(__file__).resolve()), '--worker', str(pid)],
                                       stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.DEVNULL,
                                       timeout=TIMEOUT_SECONDS, check=False)
            if completed.returncode:
                return _empty(pid, 'error', 'helper-exited')
            output.seek(0)
            raw = output.read(MAX_OUTPUT_BYTES + 1)
        if len(raw) > MAX_OUTPUT_BYTES:
            return _empty(pid, 'error', 'helper-output-limit')
        return _sanitize(json.loads(raw), pid)
    except subprocess.TimeoutExpired:
        return _empty(pid, 'timeout', 'helper-timeout')
    except (OSError, subprocess.SubprocessError):
        return _empty(pid, 'unavailable', 'helper-unavailable')
    except (ValueError, TypeError, RecursionError, OverflowError):
        return _empty(pid, 'error', 'invalid-helper-output')


class _Metadata:
    """Typed CF readers: missing values and wrong CF types always remain unknown."""
    def __init__(self):
        self.cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
        self.cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
        pointer = ctypes.c_void_p
        signatures = {
            'CFGetTypeID': ([pointer], ctypes.c_ulong),
            'CFArrayGetCount': ([pointer], ctypes.c_long),
            'CFArrayGetValueAtIndex': ([pointer, ctypes.c_long], pointer),
            'CFDictionaryGetValue': ([pointer, pointer], pointer),
            'CFNumberGetValue': ([pointer, ctypes.c_int, pointer], ctypes.c_bool),
            'CFBooleanGetValue': ([pointer], ctypes.c_bool),
            'CFStringCreateWithCString': ([pointer, ctypes.c_char_p, ctypes.c_uint32], pointer),
            'CFRelease': ([pointer], None),
        }
        for name, (arguments, result) in signatures.items():
            function = getattr(self.cf, name)
            function.argtypes, function.restype = arguments, result
        self.types = {}
        for name in ('Array', 'Dictionary', 'Number', 'Boolean'):
            function = getattr(self.cf, 'CF' + name + 'GetTypeID')
            function.argtypes, function.restype = [], ctypes.c_ulong
            self.types[name] = function()
        self.cg.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
        self.cg.CGWindowListCopyWindowInfo.restype = pointer
        self.keys = {name: pointer.in_dll(self.cg, name).value for name in (
            'kCGWindowOwnerPID', 'kCGWindowNumber', 'kCGWindowLayer', 'kCGWindowAlpha',
            'kCGWindowIsOnscreen', 'kCGWindowBounds')}

    def typed(self, value, name):
        return bool(value) and self.cf.CFGetTypeID(value) == self.types[name]

    def number(self, value, floating=False):
        if not self.typed(value, 'Number'):
            return None
        target = ctypes.c_double() if floating else ctypes.c_int64()
        if not self.cf.CFNumberGetValue(value, 6 if floating else 4, ctypes.byref(target)):
            return None
        return target.value if _number(target.value) else None

    def boolean(self, value):
        return bool(self.cf.CFBooleanGetValue(value)) if self.typed(value, 'Boolean') else None

    def field(self, row, name):
        return self.cf.CFDictionaryGetValue(row, self.keys[name])

    def named_field(self, row, name):
        key = self.cf.CFStringCreateWithCString(None, name.encode('ascii'), 0x08000100)
        if not key:
            return None
        try:
            return self.cf.CFDictionaryGetValue(row, key)
        finally:
            self.cf.CFRelease(key)

    def bounds(self, row):
        value = self.field(row, 'kCGWindowBounds')
        if not self.typed(value, 'Dictionary'):
            return None
        result = {name.lower(): self.number(self.named_field(value, name), True)
                  for name in ('X', 'Y', 'Width', 'Height')}
        return result if all(item is not None for item in result.values()) else None

    def windows(self, pid):
        values = self.cg.CGWindowListCopyWindowInfo(0, 0)
        if not values:
            return {'status': 'unavailable', 'items': []}
        try:
            if not self.typed(values, 'Array'):
                return {'status': 'error', 'items': []}
            count = self.cf.CFArrayGetCount(values)
            if not 0 <= count <= MAX_ENUMERATED_WINDOWS:
                return {'status': 'limited', 'items': []}
            rows = []
            status = 'returned'
            for index in range(count):
                row = self.cf.CFArrayGetValueAtIndex(values, index)
                if not self.typed(row, 'Dictionary') or self.number(self.field(row, 'kCGWindowOwnerPID')) != pid:
                    continue
                if len(rows) >= MAX_OWNED_WINDOWS:
                    status = 'limited'
                    break
                rows.append({'pid': pid, 'id': self.number(self.field(row, 'kCGWindowNumber')),
                             'layer': self.number(self.field(row, 'kCGWindowLayer')),
                             'alpha': self.number(self.field(row, 'kCGWindowAlpha'), True),
                             'onscreen': self.boolean(self.field(row, 'kCGWindowIsOnscreen')),
                             'bounds': self.bounds(row)})
            return {'status': status, 'items': rows}
        finally:
            self.cf.CFRelease(values)

    def session(self):
        result = {'status': 'unavailable', 'screen_locked': None, 'on_console': None, 'login_done': None}
        function = getattr(self.cg, 'CGSessionCopyCurrentDictionary', None)
        if function is None:
            return result
        function.argtypes, function.restype = [], ctypes.c_void_p
        value = function()
        if not value:
            return result
        try:
            if not self.typed(value, 'Dictionary'):
                result['status'] = 'error'
                return result
            result['status'] = 'returned'
            for field, key in (('screen_locked', 'CGSSessionScreenIsLocked'),
                               ('on_console', 'kCGSSessionOnConsoleKey'), ('login_done', 'kCGSessionLoginDoneKey')):
                result[field] = self.boolean(self.named_field(value, key))
            return result
        finally:
            self.cf.CFRelease(value)


def collect(pid):
    """Worker-only native probe; caller must isolate this from cleanup code."""
    if not _valid_pid(pid):
        return _empty(pid, 'error', 'invalid-pid')
    if sys.platform != 'darwin':
        return _empty(pid, 'unavailable', 'not-macos')
    result = _empty(pid, 'returned', 'helper-returned')
    try:
        # Direct-file execution under -I imports the package from its known
        # tools root so desktop's relative imports work in the helper too.
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from queue_checks import desktop
        result['display'] = desktop.display_state()
        metadata = _Metadata()
        for field in ('session', 'windows'):
            try:
                result[field] = metadata.session() if field == 'session' else metadata.windows(pid)
            except (OSError, AttributeError, ValueError, TypeError, OverflowError):
                result[field]['status'] = 'error'
    except (OSError, AttributeError, ValueError, TypeError, OverflowError):
        result['status'], result['reason'] = 'unavailable', 'native-probe-failed'
    return _sanitize(result, pid)


def _main():
    if len(sys.argv) != 3 or sys.argv[1] != '--worker':
        return 2
    try:
        # Bound even accidental native writes to stdout's temporary file. This
        # limit applies only to the disposable helper, never the runner.
        import resource
        resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_OUTPUT_BYTES, MAX_OUTPUT_BYTES))
        pid = int(sys.argv[2])
        result = collect(pid)
        payload = json.dumps(result, allow_nan=False, separators=(',', ':')).encode('ascii')
        if len(payload) > MAX_OUTPUT_BYTES:
            return 2
        sys.stdout.buffer.write(payload)
        return 0
    except Exception:
        # No exception messages, paths or native output cross the helper boundary.
        return 2


if __name__ == '__main__':
    raise SystemExit(_main())
