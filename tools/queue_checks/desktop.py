"""Release owned GUI clients after routing or a verified display-sleep fallback."""
from pathlib import Path
import ctypes
from datetime import datetime, timezone
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

from . import desktop_diagnostics


class IsolationError(RuntimeError):
    def __init__(self, kind, message):
        super().__init__(message)
        self.kind = kind


def timestamp():
    return {'utc': datetime.now(timezone.utc).isoformat(timespec='milliseconds'),
            'monotonic_ns': time.monotonic_ns()}


def excerpt(value, limit=4096):
    if isinstance(value, bytes):
        value = value.decode(errors='replace')
    return (value or '')[:limit]


def owned_output(value, pid):
    """Keep evidence from the PID-filtered query without persisting foreign rows."""
    clean, redacted = [], 0
    for line in value.splitlines(keepends=True):
        fields = line.rstrip('\r\n').split('|')
        if (len(fields) == 3 and fields[0].isdigit() and int(fields[0]) > 0
                and fields[1] == pid and fields[2]):
            clean.append(line)
        else:
            clean.append('[unverified window row redacted]\n')
            redacted += 1
    return ''.join(clean), redacted


def placement_failure(expected, observed, workspace):
    if not observed:
        return 'window-undiscoverable'
    if set(observed) != set(expected):
        return 'window-identity-changed'
    if any(value != workspace for value in observed.values()):
        return 'wrong-workspace'
    return None


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
        self.last_command = None
        self.evidence = {'mode': self.mode, 'requested_mode': self.requested_mode,
                         'workspace': None, 'windows': {}, 'glfw_handles': {},
                         'client_modes': {}, 'fallback_reason': None, 'display_probes': {},
                         'discovery_probes': {}, 'wake_graces': {},
                         'observations': {}, 'last_verified': {}, 'incidents': []}
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
        observation = {'started': timestamp(), 'command': list(args)}
        self.last_command = observation
        try:
            result = subprocess.run([self.binary, *args], check=True, capture_output=True,
                                    text=True, timeout=5)
            observation.update(status='returned', returncode=getattr(result, 'returncode', 0),
                               stdout=excerpt(result.stdout), stderr=excerpt(getattr(result, 'stderr', '')),
                               stdout_truncated=len(result.stdout or '') > 4096,
                               stderr_truncated=len(getattr(result, 'stderr', '') or '') > 4096)
            return result.stdout
        except (OSError, subprocess.SubprocessError) as error:
            kind = 'cli-timeout' if isinstance(error, subprocess.TimeoutExpired) else 'cli-failure'
            observation.update(status=kind, returncode=getattr(error, 'returncode', None),
                               stdout=excerpt(getattr(error, 'stdout', '')),
                               stderr=excerpt(getattr(error, 'stderr', '')), error=excerpt(str(error)),
                               stdout_truncated=len(getattr(error, 'stdout', '') or '') > 4096,
                               stderr_truncated=len(getattr(error, 'stderr', '') or '') > 4096)
            raise IsolationError(kind, 'AeroSpace isolation failed: ' + str(error)) from error
        finally:
            if args[0] == 'list-windows' and '--pid' in args and 'stdout' in observation:
                clean, count = owned_output(observation['stdout'], args[args.index('--pid') + 1])
                observation.update(stdout=excerpt(clean), stdout_redacted_rows=count,
                                   stdout_truncated=observation['stdout_truncated'] or len(clean) > 4096)
            observation['finished'] = timestamp()

    def owned(self, process):
        observation = {'started': timestamp(), 'process_before': process.poll(), 'windows': None}
        self.evidence['observations'][str(process.pid)] = observation
        if observation['process_before'] is not None:
            observation['finished'] = timestamp()
            raise IsolationError('process-exited', 'Owned client exited before window isolation')
        self.last_command = None
        try:
            raw = self.call('list-windows', '--monitor', 'all', '--pid', str(process.pid),
                            '--format', '%{window-id}|%{app-pid}|%{workspace}')
        finally:
            observation.update(command=self.last_command, process_after=process.poll(), finished=timestamp())
        if observation['process_after'] is not None:
            raise IsolationError('process-exited', 'Owned client exited during window discovery')
        rows = raw.splitlines()
        result = {}
        for row in rows:
            fields = row.split('|')
            if (len(fields) != 3 or not fields[0].isdigit() or int(fields[0]) <= 0
                    or fields[1] != str(process.pid) or not fields[2] or fields[0] in result):
                raise IsolationError('invalid-window-identity', 'AeroSpace returned a window outside the owned client PID')
            result[fields[0]] = fields[2]
        observation['windows'] = result
        return result

    def capture_incident(self, process, error, phase):
        """Collect independent evidence once; never authorize recovery from a diagnostic."""
        pid = str(process.pid)
        incident = {'at': timestamp(), 'phase': phase, 'pid': process.pid,
                    'kind': getattr(error, 'kind', 'routing-failure'), 'error': str(error),
                    'expected_windows': self.evidence['windows'].get(pid, []),
                    'expected_workspace': self.workspace,
                    'last_verified': self.evidence['last_verified'].get(pid),
                    'observation': self.evidence['observations'].get(pid),
                    'last_command': self.last_command, 'process_before_probe': process.poll()}
        # Retain the failure even if the helper crashes or a diagnostic cannot be read.
        self.evidence['incidents'].append(incident)
        if incident['process_before_probe'] is not None:
            incident['native'] = {'status': 'skipped', 'reason': 'owned-process-exited'}
        else:
            try:
                incident['native'] = desktop_diagnostics.capture(process.pid)
            except Exception as diagnostic_error:
                incident['native'] = {'status': 'error', 'reason': excerpt(str(diagnostic_error))}
        incident['process_after_probe'] = process.poll()
        if incident['process_before_probe'] is None and incident['process_after_probe'] is not None:
            # A reused numeric PID cannot establish that these windows belong to our Popen.
            incident['native'] = {'status': 'discarded', 'reason': 'owned-process-exited-during-probe'}
        incident['finished'] = timestamp()
        return incident

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
        saw_asleep = False
        wake_grace_used = False
        fallback = False
        while True:
            if process.poll() is not None:
                raise IsolationError('process-exited', 'Owned client exited before window acknowledgement')
            rows = self.owned(process)
            saw_owned = saw_owned or bool(rows)
            text = Path(log).read_text(errors='replace')
            ready = re.findall(r'\[QUEUE_TEST\] WINDOW_ROUTING_READY pid=(\d+) glfw=(\d+)', text)
            now = time.monotonic()
            if ready:
                pid, handle = ready[-1]
                if pid != str(process.pid):
                    raise IsolationError('invalid-window-identity', 'Window routing request is outside the owned client PID')
                if int(handle) <= 0:
                    raise IsolationError('invalid-window-identity', 'Owned client GLFW window handle must be nonzero')
                self.evidence['glfw_handles'][pid] = handle
                if discovery_deadline is None:
                    if now >= startup_deadline:
                        raise IsolationError('startup-timeout', 'Owned client did not report a valid WINDOW_ROUTING_READY GLFW handle '
                                           'within 120 seconds; no window acknowledged')
                    discovery_deadline = now + 30
                    probe = display_state()
                    self.evidence['discovery_probes'][pid] = probe
                    saw_asleep = probe['state'] == 'asleep'
                if rows:
                    break
            if discovery_deadline is None and now >= startup_deadline:
                raise IsolationError('startup-timeout', 'Owned client did not report a valid WINDOW_ROUTING_READY GLFW handle '
                                   'within 120 seconds; no window acknowledged')
            if discovery_deadline is not None and now >= discovery_deadline:
                if ready and not saw_owned:
                    probe = display_state()
                    self.evidence['display_probes'][str(process.pid)] = probe
                    saw_asleep = saw_asleep or probe['state'] == 'asleep'
                    if self.requested_mode != 'aerospace' and probe['state'] == 'asleep':
                        fallback = True
                        break
                    if probe['state'] == 'awake' and saw_asleep and not wake_grace_used:
                        wake_grace_used = True
                        discovery_deadline = now + 15
                        self.evidence['wake_graces'][pid] = {
                            'seconds': 15, 'reason': 'display-woke-before-window-discovery', 'probe': probe}
                        continue
                timeout = 45 if wake_grace_used else 30
                raise IsolationError('discovery-timeout', f'Owned client window was not detected by AeroSpace within {timeout} seconds; '
                                   'current desktop fallback requires sleeping displays and an owned GLFW handle')
            time.sleep(0.1)
        if fallback:
            if process.poll() is not None:
                raise IsolationError('process-exited', 'Owned client exited before window acknowledgement')
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
            raise IsolationError('process-exited', 'Owned client exited before window acknowledgement')
        gate = Path(cache) / 'Lua/test-window-routed.txt'
        with gate.open('x') as stream:
            stream.write(pid + ':' + handle + '\n')
        self.record_placement(process, placed)

    def place(self, process, rows):
        """Move exactly the discovered owned windows without affecting global focus."""
        for window in rows:
            # Revalidate the process and exact ID before every mutation; never act on global focus.
            observed = self.owned(process)
            if window not in observed:
                raise IsolationError('window-identity-changed' if observed else 'window-undiscoverable',
                                     'Owned client window disappeared before routing')
            self.call('layout', '--window-id', window, 'floating')
            observed = self.owned(process)
            if window not in observed:
                raise IsolationError('window-identity-changed' if observed else 'window-undiscoverable',
                                     'Owned client window disappeared before moving')
            self.call('move-node-to-workspace', '--window-id', window, self.workspace)
        placed = self.owned(process)
        kind = placement_failure(rows, placed, self.workspace)
        if kind:
            raise IsolationError(kind, 'AeroSpace did not isolate all owned client windows')
        return placed

    def record_placement(self, process, placed):
        self.evidence['windows'][str(process.pid)] = list(placed)
        self.evidence['client_modes'][str(process.pid)] = 'aerospace'
        self.mode = 'current' if 'current' in self.evidence['client_modes'].values() else 'aerospace'
        self.evidence.update(mode=self.mode, workspace=None if self.mode == 'current' else self.workspace)
        self.record_verified(process, placed)

    def record_verified(self, process, rows):
        pid = str(process.pid)
        self.evidence['last_verified'][pid] = {'at': timestamp(), 'windows': dict(rows),
                                             'observation': self.evidence['observations'].get(pid)}

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
            kind = placement_failure(placed, observed, self.workspace)
            if kind:
                raise IsolationError(kind, 'Owned client window changed before visibility acknowledgement')
            if process.poll() is not None:
                raise IsolationError('process-exited', 'Owned client exited before visibility acknowledgement')
            # link() publishes a closed, complete file and refuses existing files or symlinks.
            os.link(temporary, gate)
        finally:
            temporary.unlink(missing_ok=True)

    def check(self, process):
        if self.evidence['client_modes'].get(str(process.pid)) == 'current':
            if process.poll() is not None:
                raise IsolationError('process-exited', 'Owned client exited during current-desktop run')
            rows = self.owned(process)
            placed = self.place(process, rows) if rows else None
            if process.poll() is not None:
                raise IsolationError('process-exited', 'Owned client exited during current-desktop run')
            if placed:
                # Current-desktop windows stay transparent until this separate recovery token.
                self.acknowledge_visible(process, placed)
                self.record_placement(process, placed)
            return
        # Observation is allowed; only window ownership and placement define isolation.
        rows = self.owned(process)
        expected = self.evidence['windows'].get(str(process.pid), [])
        kind = placement_failure(expected, rows, self.workspace)
        if kind:
            message = {'window-undiscoverable': 'Owned client window is no longer discoverable',
                       'window-identity-changed': 'Owned client window identities changed',
                       'wrong-workspace': 'Owned client window escaped its isolated test workspace'}[kind]
            raise IsolationError(kind, message + ': '
                                 f'pid={process.pid}, expected={expected!r} on {self.workspace!r}, observed={rows!r}')
        self.record_verified(process, rows)


def prepare(selection):
    return Desktop(selection)
