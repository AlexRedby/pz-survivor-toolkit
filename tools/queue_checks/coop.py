"""The real CoopServer shares its owner's cache; keep its evidence separate."""
from pathlib import Path
import json
import re
import shutil
import sys
import time


def enabled(selection):
    options = selection.get('options', {})
    if not isinstance(options, dict):
        raise ValueError('Suite options must be an object')
    value = options.get('mp_host', False)
    if type(value) is not bool or value and selection.get('kind') != 'mp':
        raise ValueError('mp_host must be boolean and requires MP')
    if value and any(selection.get('options', {}).get(key) for key in ('seed_run', 'startup_connection')):
        raise ValueError('Host requires sealed world templates and the fixture client identities')
    return value


def stage(root, runtime):
    cache = Path(root) / 'client1'
    shutil.copytree(Path(root) / 'server/Server', cache / 'Server')
    runtime['host_cache'] = str(cache)
    # The bounded Windows path can lack ProcessHandle argv; retain its existing
    # qualification scope rather than claiming this new observation there.
    if sys.platform != 'win32':
        runtime['host_child_diagnostics_protocol'] = 1


def loader_options(agent):
    # JDK_JAVA_OPTIONS is parsed again by Host's child JVM, including paths with spaces.
    if any(char in agent for char in ('"', '\n', '\r')):
        raise ValueError('Host loader options cannot contain quotes or newlines')
    return '"' + agent + '" --enable-native-access=ALL-UNNAMED --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED'


def mirror_logs(root):
    root = Path(root)
    cache = root / 'client1'
    for name, target in (("host-child-stderr.log", "server-stderr.log"),
                         ("host-child-diagnostics.json", "server-startup-diagnostics.json")):
        source = cache / name
        if source.is_file():
            shutil.copyfile(source, root / target)
    console = cache / 'coop-console.txt'
    if console.is_file():
        shutil.copyfile(console, root / 'server-launch.log')
    for path in (cache / 'Logs').rglob('*DebugLog-server.txt'):
        target = root / 'server/Logs' / path.relative_to(cache / 'Logs')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)


def child(text, parent):
    matches = re.findall(r'\[QUEUE_TEST\] HOST_CHILD pid=(\d+) parent=(\d+)(?:\s|$)', text)
    if len(matches) != 1 or int(matches[0][1]) != parent or int(matches[0][0]) <= 0 or int(matches[0][0]) == parent:
        raise RuntimeError('Host did not prove one native child of the owned client')
    return int(matches[0][0])


def save_host(process, child_pid, read_text, timeout=35):
    """Ask the existing owner launcher to save/quit its proven native CoopMaster child."""
    if type(child_pid) is not int or child_pid <= 0 or child_pid == process.pid or process.poll() is not None:
        raise RuntimeError('Host save requires its live owner and proven child PID')
    try:
        process.stdin.write('QUEUE_HOST_SAVE_QUIT\n')
        process.stdin.flush()
    except (AttributeError, BrokenPipeError, OSError) as error:
        raise RuntimeError('Host save request failed: ' + str(error)) from error
    deadline = time.monotonic() + timeout
    while True:
        text = read_text()
        if '[QUEUE_TEST] FAIL host save' in text:
            raise RuntimeError('Host launcher refused or failed its save/quit request')
        matches = re.findall(r'\[QUEUE_TEST\] HOST_SAVED_EXIT pid=(\d+) exit=(-?\d+)(?:\s|$)', text)
        if matches:
            if len(matches) != 1 or int(matches[0][0]) != child_pid or int(matches[0][1]) != 0:
                raise RuntimeError('Host save did not prove its original child exited successfully')
            return {'pid': child_pid, 'exit_code': 0}
        if process.poll() is not None or time.monotonic() >= deadline:
            raise RuntimeError('Host save/quit acknowledgement timed out or owner exited')
        time.sleep(0.1)


def startup_diagnostic_issues(root, processes):
    """Startup observation never substitutes for native readiness or effects."""
    root = Path(root)
    metadata, stderr = root / 'server-startup-diagnostics.json', root / 'server-stderr.log'
    try:
        if (metadata.is_symlink() or stderr.is_symlink() or not metadata.is_file() or not stderr.is_file()
                or metadata.stat().st_size > 65536 or stderr.stat().st_size > 262144):
            raise ValueError('missing, linked or oversized capture')
        value = json.loads(metadata.read_text(encoding='utf-8'))
        fields = {'schema','pid','parent','argv','argvComplete','credentialsRedacted','stderrCaptureStarted',
                  'stderrEof','stderrBytes','stderrCapturedBytes','stderrTruncated','stderrError',
                  'processExited','exitCode','diagnosticsError','stdoutUntouched','stdinUntouched','readinessEvidence'}
        if type(value) is not dict or set(value) != fields or type(value['schema']) is not int or value['schema'] != 1:
            raise ValueError('unsupported metadata')
        for key, role in (('pid','server'), ('parent','client1')):
            if type(value[key]) is not int or value[key] <= 0 or value[key] != processes[role]['pid']:
                raise ValueError('child ownership')
        argv = value['argv']
        if (value['argvComplete'] is not True or type(argv) is not list or not argv
                or any(type(arg) is not str for arg in argv) or type(value['credentialsRedacted']) is not bool
                or not {'zombie.network.GameServer','-coop','-cachedir=' + str(root / 'client1')} <= set(argv)):
            raise ValueError('incomplete child arguments')
        if (any(value[key] is not True for key in ('stderrCaptureStarted','stderrEof','processExited','stdoutUntouched','stdinUntouched'))
                or value['readinessEvidence'] is not False or value['stderrTruncated'] is not False
                or value['stderrError'] is not None or value['diagnosticsError'] is not None):
            raise ValueError('incomplete stderr/exit observation')
        if (type(value['exitCode']) is not int or value['exitCode'] != 0
                or value['exitCode'] != processes['server'].get('exit_code')):
            raise ValueError('child exit status')
        if (any(type(value[key]) is not int or value[key] < 0 for key in ('stderrBytes','stderrCapturedBytes'))
                or value['stderrBytes'] != value['stderrCapturedBytes'] or value['stderrCapturedBytes'] != stderr.stat().st_size):
            raise ValueError('stderr byte accounting')
    except (OSError, ValueError, UnicodeError, KeyError, TypeError) as error:
        return ['Host startup diagnostics incomplete: ' + str(error)]
    return []
