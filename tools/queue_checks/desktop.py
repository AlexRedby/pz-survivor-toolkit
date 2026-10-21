"""Release owned GUI clients after routing or a verified display-sleep fallback."""
from pathlib import Path
import ctypes
import re
import shutil
import subprocess
import sys
import time


def display_state():
    """Read display sleep without waking, changing, or focusing any display."""
    unknown = {'state': 'unknown', 'displays': []}
    if sys.platform != 'darwin':
        return unknown
    try:
        graphics = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
        display_id = ctypes.c_uint32
        graphics.CGGetOnlineDisplayList.argtypes = [ctypes.c_uint32, ctypes.POINTER(display_id),
                                                  ctypes.POINTER(ctypes.c_uint32)]
        graphics.CGGetOnlineDisplayList.restype = ctypes.c_int32
        graphics.CGDisplayIsAsleep.argtypes = [display_id]
        graphics.CGDisplayIsAsleep.restype = ctypes.c_uint32  # Darwin boolean_t
        count = ctypes.c_uint32()
        if graphics.CGGetOnlineDisplayList(0, None, ctypes.byref(count)) or not 0 < count.value <= 128:
            return unknown
        capacity = count.value
        displays = (display_id * capacity)()
        if graphics.CGGetOnlineDisplayList(capacity, displays, ctypes.byref(count)) or not 0 < count.value <= capacity:
            return unknown
        ids = list(displays)[:count.value]
        if 0 in ids or len(set(ids)) != len(ids):
            return unknown
        rows = [{'id': value, 'asleep': bool(graphics.CGDisplayIsAsleep(value))} for value in ids]
        return {'state': 'asleep' if all(row['asleep'] for row in rows) else 'awake', 'displays': rows}
    except (OSError, AttributeError, TypeError, ValueError):
        return unknown


class Desktop:
    def __init__(self, selection):
        options = selection.get('options', {})
        self.requested_mode = options.get('desktop_mode', 'auto')
        if self.requested_mode not in ('auto', 'aerospace', 'current'):
            raise ValueError('desktop_mode must be auto, aerospace or current')
        self.mode = 'aerospace'
        self.evidence = {'mode': self.mode, 'requested_mode': self.requested_mode,
                         'workspace': None, 'windows': {}, 'glfw_handles': {},
                         'client_modes': {}, 'fallback_reason': None, 'display_probe': display_state()}
        if self.requested_mode == 'current':
            if self.evidence['display_probe']['state'] != 'asleep':
                raise RuntimeError('Current desktop fallback requires confirmed sleeping displays; no game launched')
        self.workspace = options.get('test_workspace', 'PZ-TEST')
        if not isinstance(self.workspace, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', self.workspace):
            raise ValueError('test_workspace must be a workspace name using letters, digits, - or _')
        self.binary = shutil.which('aerospace')
        if not self.binary:
            raise RuntimeError('AeroSpace is required for isolated macOS native tests; no game launched')
        version = self.call('--version').strip()
        if not re.search(r'\b\d+\.\d+\.\d+\b', version):
            raise RuntimeError('AeroSpace returned a malformed version; no game launched')
        self.evidence.update(workspace=self.workspace, version=version)

    def call(self, *args):
        try:
            return subprocess.run([self.binary, *args], check=True, capture_output=True,
                                  text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError) as error:
            raise RuntimeError('AeroSpace isolation failed: ' + str(error)) from error

    def owned(self, process):
        if process.poll() is not None:
            raise RuntimeError('Owned client exited before window isolation')
        rows = self.call('list-windows', '--monitor', 'all', '--pid', str(process.pid),
                         '--format', '%{window-id}|%{app-pid}|%{workspace}').splitlines()
        result = {}
        for row in rows:
            fields = row.split('|')
            if (len(fields) != 3 or not fields[0].isdigit() or int(fields[0]) <= 0
                    or fields[1] != str(process.pid) or not fields[2] or fields[0] in result):
                raise RuntimeError('AeroSpace returned a window outside the owned client PID')
            result[fields[0]] = fields[2]
        return result

    def arguments(self, cache, classes):
        agent = Path(classes) / 'test-window-agent.jar'
        if not agent.is_file():
            raise RuntimeError('Prepared macOS test-window agent is missing; prepare a fresh run')
        gate = Path(cache) / 'Lua/test-window-routed.txt'
        if gate.exists() or gate.is_symlink():
            raise RuntimeError('Test-window routing acknowledgement already exists; prepare a fresh run')
        return ['-javaagent:' + str(agent),
                '-Dtoolkit.test.windowGate=' + str(gate)]

    def route(self, process, cache, log):
        deadline = time.monotonic() + 30
        saw_owned = False
        fallback = False
        while True:
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before window acknowledgement')
            rows = self.owned(process)
            saw_owned = saw_owned or bool(rows)
            text = Path(log).read_text(errors='replace')
            ready = re.findall(r'\[QUEUE_TEST\] WINDOW_ROUTING_READY pid=(\d+) glfw=(\d+)', text)
            if ready:
                pid, handle = ready[-1]
                if pid != str(process.pid):
                    raise RuntimeError('Window routing request is outside the owned client PID')
                if int(handle) <= 0:
                    raise RuntimeError('Owned client GLFW window handle must be nonzero')
                if rows:
                    break
            if time.monotonic() >= deadline:
                if self.requested_mode != 'aerospace' and ready and not saw_owned:
                    probe = display_state()
                    self.evidence['display_probe'] = probe
                    if probe['state'] == 'asleep':
                        fallback = True
                        break
                raise RuntimeError('Owned client window was not detected by AeroSpace within 30 seconds; '
                                   'current desktop fallback requires sleeping displays and an owned GLFW handle')
            time.sleep(0.1)
        if fallback:
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before window acknowledgement')
            (Path(cache) / 'Lua/test-window-routed.txt').write_text(pid + ':' + handle + '\n')
            self.mode = 'current'
            self.evidence.update(mode='current', workspace=None,
                                 fallback_reason='display-asleep-owned-window-discovery-timeout')
            self.evidence['glfw_handles'][pid] = handle
            self.evidence['client_modes'][pid] = 'current'
            return
        for window in rows:
            # Revalidate the process and exact ID before every mutation; never act on global focus.
            if window not in self.owned(process):
                raise RuntimeError('Owned client window disappeared before routing')
            self.call('layout', '--window-id', window, 'floating')
            if window not in self.owned(process):
                raise RuntimeError('Owned client window disappeared before moving')
            self.call('move-node-to-workspace', '--window-id', window, self.workspace)
        placed = self.owned(process)
        if not placed or any(workspace != self.workspace for workspace in placed.values()):
            raise RuntimeError('AeroSpace did not isolate all owned client windows')
        gate = Path(cache) / 'Lua/test-window-routed.txt'
        gate.write_text(pid + ':' + handle + '\n')
        self.evidence['windows'][str(process.pid)] = list(placed)
        self.evidence['client_modes'][str(process.pid)] = 'aerospace'

    def check(self, process):
        if str(process.pid) in self.evidence['glfw_handles']:
            if process.poll() is not None:
                raise RuntimeError('Owned client exited during current-desktop run')
            return
        # Observation is allowed; only window ownership and placement define isolation.
        rows = self.owned(process)
        expected = self.evidence['windows'].get(str(process.pid), [])
        if not rows or set(rows) != set(expected) or any(workspace != self.workspace for workspace in rows.values()):
            raise RuntimeError('Owned client window escaped its isolated test workspace: '
                               f'pid={process.pid}, expected={expected!r} on {self.workspace!r}, observed={rows!r}')


def prepare(selection):
    return Desktop(selection)
