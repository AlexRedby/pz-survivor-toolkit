"""Release owned GUI clients after the explicitly selected desktop policy."""
from pathlib import Path
import re
import shutil
import subprocess
import time


class Desktop:
    def __init__(self, selection):
        options = selection.get('options', {})
        self.mode = options.get('desktop_mode', 'aerospace')
        if self.mode not in ('aerospace', 'current'):
            raise ValueError('desktop_mode must be aerospace or current')
        self.evidence = {'mode': self.mode, 'workspace': None, 'windows': {}}
        if self.mode == 'current':
            # No workspace placement is promised in this opt-in mode.
            self.evidence['glfw_handles'] = {}
            return
        self.workspace = options.get('test_workspace', 'PZ-TEST')
        if not isinstance(self.workspace, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', self.workspace):
            raise ValueError('test_workspace must be a workspace name using letters, digits, - or _')
        self.binary = shutil.which('aerospace')
        if not self.binary:
            raise RuntimeError('AeroSpace is required for isolated macOS native tests; no game launched')
        self.evidence.update(workspace=self.workspace, version=self.call('--version').strip())

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
        deadline = time.monotonic() + 30
        while True:
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before window acknowledgement')
            rows = self.owned(process) if self.mode == 'aerospace' else {}
            text = Path(log).read_text(errors='replace')
            ready = re.findall(r'\[QUEUE_TEST\] WINDOW_ROUTING_READY pid=(\d+) glfw=(\d+)', text)
            if ready:
                pid, handle = ready[-1]
                if pid != str(process.pid):
                    raise RuntimeError('Window routing request is outside the owned client PID')
                if rows or self.mode == 'current':
                    break
            if time.monotonic() >= deadline:
                if self.mode == 'aerospace':
                    raise RuntimeError('Owned client window was not detected by AeroSpace within 30 seconds')
                raise RuntimeError('Owned client GLFW window was not ready within 30 seconds')
            time.sleep(0.1)
        if self.mode == 'current':
            if process.poll() is not None:
                raise RuntimeError('Owned client exited before window acknowledgement')
            (Path(cache) / 'Lua/test-window-routed.txt').write_text(pid + ':' + handle + '\n')
            self.evidence['glfw_handles'][pid] = handle
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

    def check(self, process):
        if self.mode == 'current':
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
