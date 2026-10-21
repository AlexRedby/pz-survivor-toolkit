"""Prefer AeroSpace placement, then release owned clients on their current desktop."""
from pathlib import Path
import re
import shutil
import subprocess
import time


class AeroSpaceUnavailable(RuntimeError):
    """Placement failed without invalidating the owned process/window identity."""


class Desktop:
    def __init__(self, selection):
        options = selection.get('options', {})
        self.requested_mode = options.get('desktop_mode', 'auto')
        if self.requested_mode not in ('auto', 'aerospace', 'current'):
            raise ValueError('desktop_mode must be auto, aerospace or current')
        self.mode = 'aerospace'
        self.evidence = {'mode': self.mode, 'requested_mode': self.requested_mode,
                         'workspace': None, 'windows': {}, 'glfw_handles': {},
                         'client_modes': {}, 'fallback_reason': None}
        self.workspace = options.get('test_workspace', 'PZ-TEST')
        if not isinstance(self.workspace, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', self.workspace):
            raise ValueError('test_workspace must be a workspace name using letters, digits, - or _')
        self.binary = shutil.which('aerospace')
        self.available = True
        try:
            if not self.binary:
                raise AeroSpaceUnavailable('AeroSpace is unavailable; no game launched yet')
            version = self.call('--version').strip()
            if not re.search(r'\b\d+\.\d+\.\d+\b', version):
                raise AeroSpaceUnavailable('AeroSpace returned a malformed version; no game launched yet')
            self.evidence.update(workspace=self.workspace, version=version)
        except AeroSpaceUnavailable as error:
            self.unavailable(error)

    def unavailable(self, error):
        if self.requested_mode == 'aerospace':
            raise error
        self.available = False
        self.evidence['aerospace_error'] = str(error)

    def call(self, *args):
        try:
            return subprocess.run([self.binary, *args], check=True, capture_output=True,
                                  text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError) as error:
            raise AeroSpaceUnavailable('AeroSpace isolation failed: ' + str(error)) from error

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

    def acknowledge_current(self, process, cache, pid, handle, reason):
        if process.poll() is not None:
            raise RuntimeError('Owned client exited before window acknowledgement')
        (Path(cache) / 'Lua/test-window-routed.txt').write_text(pid + ':' + handle + '\n')
        self.mode = 'current'
        self.evidence.update(mode='current', workspace=None, fallback_reason=reason)
        self.evidence['glfw_handles'][pid] = handle
        self.evidence['client_modes'][pid] = 'current'

    def place(self, process, rows):
        for window in rows:
            # Revalidate the process and exact ID before every mutation; never act on global focus.
            if window not in self.owned(process):
                raise AeroSpaceUnavailable('Owned client window disappeared before routing')
            self.call('layout', '--window-id', window, 'floating')
            if window not in self.owned(process):
                raise AeroSpaceUnavailable('Owned client window disappeared before moving')
            self.call('move-node-to-workspace', '--window-id', window, self.workspace)
        placed = self.owned(process)
        if not placed or any(workspace != self.workspace for workspace in placed.values()):
            raise AeroSpaceUnavailable('AeroSpace did not isolate all owned client windows')
        return placed

    def route(self, process, cache, log):
        deadline = time.monotonic() + 30
        while True:
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before window acknowledgement')
            rows = {}
            if self.available:
                try:
                    rows = self.owned(process)
                except AeroSpaceUnavailable as error:
                    self.unavailable(error)
            text = Path(log).read_text(errors='replace')
            ready = re.findall(r'\[QUEUE_TEST\] WINDOW_ROUTING_READY pid=(\d+) glfw=(\d+)', text)
            if ready:
                pid, handle = ready[-1]
                if pid != str(process.pid):
                    raise RuntimeError('Window routing request is outside the owned client PID')
                if int(handle) <= 0:
                    raise RuntimeError('Owned client GLFW window handle must be nonzero')
                if rows:
                    try:
                        placed = self.place(process, rows)
                    except AeroSpaceUnavailable as error:
                        self.unavailable(error)
                        return self.acknowledge_current(process, cache, pid, handle, 'aerospace-routing-unavailable')
                    if process.poll() is not None:
                        raise RuntimeError('Owned client exited before window acknowledgement')
                    (Path(cache) / 'Lua/test-window-routed.txt').write_text(pid + ':' + handle + '\n')
                    self.evidence['windows'][pid] = list(placed)
                    self.evidence['client_modes'][pid] = 'aerospace'
                    return
                if not self.available:
                    return self.acknowledge_current(process, cache, pid, handle, 'aerospace-unavailable')
            if time.monotonic() >= deadline:
                if self.requested_mode != 'aerospace' and ready:
                    return self.acknowledge_current(process, cache, pid, handle, 'owned-window-discovery-timeout')
                raise RuntimeError('Owned client window was not detected by AeroSpace within 30 seconds; '
                                   'current desktop fallback requires an owned GLFW handle and auto/current policy')
            time.sleep(0.1)

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
