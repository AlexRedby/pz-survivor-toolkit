"""Release owned GUI clients after routing or a verified display-sleep fallback."""
from pathlib import Path
import ctypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time


def display_state():
    """Read online-display sleep through CoreGraphics without changing display state."""
    def unknown(reason):
        return {'state': 'unknown', 'displays': [], 'reason': reason}

    if sys.platform != 'darwin':
        return unknown('not-macos')
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
            return unknown('invalid-online-display-count')
        capacity = count.value
        displays = (display_id * capacity)()
        if graphics.CGGetOnlineDisplayList(capacity, displays, ctypes.byref(count)) or count.value != capacity:
            return unknown('online-display-enumeration-changed-or-failed')
        ids = list(displays)
        if 0 in ids or len(set(ids)) != len(ids):
            return unknown('invalid-online-display-identities')
        rows = [{'id': value, 'asleep': bool(graphics.CGDisplayIsAsleep(value))} for value in ids]
        # A newly online display could be omitted by the bounded fetch above.
        if graphics.CGGetOnlineDisplayList(0, None, ctypes.byref(count)) or count.value != len(ids):
            return unknown('online-display-count-changed-or-failed')
        return {'state': 'asleep' if all(row['asleep'] for row in rows) else 'awake', 'displays': rows}
    except (OSError, AttributeError, TypeError, ValueError) as error:
        return unknown(type(error).__name__ + ': ' + str(error))


def require_gui_access():
    """Reject an inaccessible GUI session before launching a native client."""
    probe = display_state()
    if probe['state'] not in ('awake', 'asleep'):
        raise RuntimeError('GUI display access unavailable (' + probe.get('reason', 'unknown probe')
                           + '); run this command outside the sandbox in the logged-in macOS session; '
                           'no game launched. Waking the display is not a remedy for inaccessible CoreGraphics.')
    return probe


class Desktop:
    def __init__(self, selection):
        options = selection.get('options', {})
        self.requested_mode = options.get('desktop_mode', 'auto')
        if self.requested_mode not in ('auto', 'aerospace', 'current'):
            raise ValueError('desktop_mode must be auto, aerospace or current')
        self.mode = 'aerospace'
        self.recovery_gates = {}
        self.evidence = {'mode': self.mode, 'requested_mode': self.requested_mode,
                         'workspace': None, 'windows': {}, 'glfw_handles': {},
                         'client_modes': {}, 'fallback_reason': None, 'display_probes': {}}
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
        visible = gate.with_name('test-window-visible.txt')
        if any(path.exists() or path.is_symlink() for path in (gate, visible)):
            raise RuntimeError('Test-window routing acknowledgement already exists; prepare a fresh run')
        return ['-javaagent:' + str(agent),
                '-Dtoolkit.test.windowGate=' + str(gate)]

    def route(self, process, cache, log):
        startup_deadline = time.monotonic() + 120
        discovery_deadline = None
        saw_owned = False
        fallback = False
        while True:
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before window acknowledgement')
            rows = self.owned(process)
            saw_owned = saw_owned or bool(rows)
            text = Path(log).read_text(errors='replace')
            ready = re.findall(r'\[QUEUE_TEST\] WINDOW_ROUTING_READY pid=(\d+) glfw=(\d+)', text)
            now = time.monotonic()
            if ready:
                pid, handle = ready[-1]
                if pid != str(process.pid):
                    raise RuntimeError('Window routing request is outside the owned client PID')
                if int(handle) <= 0:
                    raise RuntimeError('Owned client GLFW window handle must be nonzero')
                if discovery_deadline is None:
                    if now >= startup_deadline:
                        raise RuntimeError('Owned client did not report a valid WINDOW_ROUTING_READY GLFW handle '
                                           'within 120 seconds; no window acknowledged')
                    discovery_deadline = now + 30
                if rows:
                    break
            if discovery_deadline is None and now >= startup_deadline:
                raise RuntimeError('Owned client did not report a valid WINDOW_ROUTING_READY GLFW handle '
                                   'within 120 seconds; no window acknowledged')
            if discovery_deadline is not None and now >= discovery_deadline:
                if self.requested_mode != 'aerospace' and ready and not saw_owned:
                    probe = display_state()
                    self.evidence['display_probes'][str(process.pid)] = probe
                    if probe['state'] == 'asleep':
                        fallback = True
                        break
                raise RuntimeError('Owned client window was not detected by AeroSpace within 30 seconds; '
                                   'current desktop fallback requires sleeping displays and an owned GLFW handle')
            time.sleep(0.1)
        if fallback:
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before window acknowledgement')
            with (Path(cache) / 'Lua/test-window-routed.txt').open('x') as gate:
                gate.write(pid + ':' + handle + ':current\n')
            self.mode = 'current'
            self.evidence.update(mode='current', workspace=None,
                                 fallback_reason='display-asleep-owned-window-discovery-timeout')
            self.evidence['glfw_handles'][pid] = handle
            self.evidence['client_modes'][pid] = 'current'
            self.recovery_gates[pid] = Path(cache) / 'Lua/test-window-visible.txt'
            return
        placed = self.place(process, rows)
        if process.poll() is not None:
            raise RuntimeError('Owned client exited before window acknowledgement')
        gate = Path(cache) / 'Lua/test-window-routed.txt'
        with gate.open('x') as stream:
            stream.write(pid + ':' + handle + '\n')
        self.record_placement(process, placed)

    def place(self, process, rows):
        """Move exactly the discovered owned windows without affecting global focus."""
        for window in rows:
            # Revalidate the process and exact ID before every mutation; never act on global focus.
            if window not in self.owned(process):
                raise RuntimeError('Owned client window disappeared before routing')
            self.call('layout', '--window-id', window, 'floating')
            if window not in self.owned(process):
                raise RuntimeError('Owned client window disappeared before moving')
            self.call('move-node-to-workspace', '--window-id', window, self.workspace)
        placed = self.owned(process)
        if set(placed) != set(rows) or any(workspace != self.workspace for workspace in placed.values()):
            raise RuntimeError('AeroSpace did not isolate all owned client windows')
        return placed

    def record_placement(self, process, placed):
        self.evidence['windows'][str(process.pid)] = list(placed)
        self.evidence['client_modes'][str(process.pid)] = 'aerospace'
        self.mode = 'current' if 'current' in self.evidence['client_modes'].values() else 'aerospace'
        self.evidence.update(mode=self.mode, workspace=None if self.mode == 'current' else self.workspace)

    def acknowledge_visible(self, process, placed):
        """Publish a complete recovery token exclusively, after the last ownership check."""
        pid = str(process.pid)
        gate = self.recovery_gates[pid]
        descriptor, name = tempfile.mkstemp(prefix='.test-window-visible-', dir=gate.parent)
        temporary = Path(name)
        try:
            with os.fdopen(descriptor, 'w') as stream:
                stream.write(pid + ':' + self.evidence['glfw_handles'][pid] + '\n')
            observed = self.owned(process)
            if set(observed) != set(placed) or any(workspace != self.workspace for workspace in observed.values()):
                raise RuntimeError('Owned client window changed before visibility acknowledgement')
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before visibility acknowledgement')
            # link() publishes a closed, complete file and refuses existing files or symlinks.
            os.link(temporary, gate)
        finally:
            temporary.unlink(missing_ok=True)

    def check(self, process):
        if self.evidence['client_modes'].get(str(process.pid)) == 'current':
            if process.poll() is not None:
                raise RuntimeError('Owned client exited during current-desktop run')
            rows = self.owned(process)
            placed = self.place(process, rows) if rows else None
            if process.poll() is not None:
                raise RuntimeError('Owned client exited during current-desktop run')
            if placed:
                # Current-desktop windows stay transparent until this separate recovery token.
                self.acknowledge_visible(process, placed)
                self.record_placement(process, placed)
            return
        # Observation is allowed; only window ownership and placement define isolation.
        rows = self.owned(process)
        expected = self.evidence['windows'].get(str(process.pid), [])
        if not rows or set(rows) != set(expected) or any(workspace != self.workspace for workspace in rows.values()):
            raise RuntimeError('Owned client window escaped its isolated test workspace: '
                               f'pid={process.pid}, expected={expected!r} on {self.workspace!r}, observed={rows!r}')


def prepare(selection):
    return Desktop(selection)
