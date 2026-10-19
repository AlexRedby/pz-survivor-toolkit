"""Route only this run's GUI clients to an inactive AeroSpace workspace."""
from pathlib import Path
import re
import shutil
import subprocess
import time


class Desktop:
    def __init__(self, selection, manual=False):
        self.manual = manual
        self.workspace = selection.get('options', {}).get('test_workspace', 'PZ-TEST')
        if not isinstance(self.workspace, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', self.workspace):
            raise ValueError('test_workspace must be a workspace name using letters, digits, - or _')
        self.binary = shutil.which('aerospace')
        if not self.binary:
            raise RuntimeError('AeroSpace is required for isolated macOS native tests; no game launched')
        self.evidence = {'workspace': self.workspace, 'manual_inspection': manual, 'windows': {}, 'version': self.call('--version').strip()}
        self.require_inactive()
        self.evidence['initial_focus'] = self.call('list-windows', '--focused', '--format', '%{window-id}').strip()

    def call(self, *args):
        try:
            return subprocess.run([self.binary, *args], check=True, capture_output=True,
                                  text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError) as error:
            raise RuntimeError('AeroSpace isolation failed: ' + str(error)) from error

    def require_inactive(self):
        visible = self.call('list-workspaces', '--monitor', 'all', '--visible', '--format', '%{workspace}').splitlines()
        if not visible:
            raise RuntimeError('AeroSpace did not report an active workspace; isolation cannot be verified')
        if self.workspace in visible:
            raise RuntimeError('Test workspace ' + self.workspace + ' is visible; select another workspace before running tests')

    def owned(self, process):
        if process.poll() is not None:
            raise RuntimeError('Owned client exited before window isolation')
        rows = self.call('list-windows', '--monitor', 'all', '--pid', str(process.pid),
                         '--format', '%{window-id}|%{app-pid}|%{workspace}').splitlines()
        result = {}
        for row in rows:
            fields = row.split('|')
            if len(fields) != 3 or not fields[0].isdigit() or fields[1] != str(process.pid):
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
        self.require_inactive()
        deadline = time.monotonic() + 30
        while True:
            rows = self.owned(process)
            text = Path(log).read_text(errors='replace')
            ready = re.findall(r'\[QUEUE_TEST\] WINDOW_ROUTING_READY pid=(\d+) glfw=(\d+)', text)
            if rows and ready:
                pid, handle = ready[-1]
                if pid != str(process.pid):
                    raise RuntimeError('Window routing request is outside the owned client PID')
                break
            if time.monotonic() >= deadline:
                raise RuntimeError('Owned client window was not detected by AeroSpace within 30 seconds')
            time.sleep(0.1)
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
        focused = self.call('list-windows', '--focused', '--format', '%{app-pid}').strip()
        if focused == str(process.pid):
            raise RuntimeError('Owned test client unexpectedly received keyboard focus')
        self.require_inactive()
        gate = Path(cache) / 'Lua/test-window-routed.txt'
        gate.write_text(pid + ':' + handle + '\n')
        self.evidence['windows'][str(process.pid)] = list(placed)
        self.evidence['last_focus'] = self.call('list-windows', '--focused', '--format', '%{window-id}').strip()

    def check(self, process):
        # Manual fixtures may be visited by the user after the same silent initial routing.
        if not self.manual:
            self.require_inactive()
            if self.call('list-windows', '--focused', '--format', '%{app-pid}').strip() == str(process.pid):
                raise RuntimeError('Owned test client unexpectedly received keyboard focus')
        rows = self.owned(process)
        expected = self.evidence['windows'].get(str(process.pid), [])
        if not rows or set(rows) != set(expected) or any(workspace != self.workspace for workspace in rows.values()):
            raise RuntimeError('Owned client window escaped its isolated test workspace')


def prepare(selection, manual=False):
    return Desktop(selection, manual=manual)
